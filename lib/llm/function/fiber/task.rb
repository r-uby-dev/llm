# frozen_string_literal: true

module LLM::Function::Fiber
  ##
  # {LLM::Function::Fiber::Task LLM::Function::Fiber::Task}
  # wraps a function call in a scheduler-backed fiber for
  # cooperative concurrent execution. The fiber is created
  # lazily when {#wait} is called, not at construction time.
  #
  # Requires `Fiber.scheduler` — without one, raise early in
  # {#wait}. Interrupting a running task raises
  # {LLM::Interrupt} on the fiber, which stops it at the next
  # yield point. A cancel that arrives before the fiber exists
  # is held rather than dropped, and spent by the fiber itself
  # when it starts.
  #
  # A tool that implements `on_interrupt` is told on that fiber, once the
  # call has ended, rather than on the thread that cancelled it.
  class Task < LLM::Function::Task
    ##
    # @param [LLM::Function] fn
    # @param [Hash] options
    def initialize(fn, options = {})
      super
    end

    ##
    # @return [nil]
    def spawn
      return if @guarded
      if Fiber.scheduler.nil?
        raise ArgumentError, "Fiber concurrency requires Fiber.scheduler"
      else
        ##
        # The body hands its ending back through a queue, the way
        # `LLM::Function::Async::Task` does, rather than through the fiber.
        #
        # **A fiber is not askable.** `Fiber.schedule` under `Async` returns
        # `Async::Scheduler#fiber`'s value, which is a plain fiber, and a
        # plain fiber has no `#value`; a fiber that has ended cannot be
        # resumed for one either. The result, and the exception a body ended
        # with, are therefore pushed where they can be taken from.
        #
        # The fiber also names itself, because the scheduler's return is not
        # promised: under `Async` it is nil for a block that has already
        # ended, and a block that raises on its first instruction - a held
        # cancel - is exactly that. `@fiber` is the return when there is one,
        # and that name when there is not.
        #
        # The scheduler is named here too, and not read in {#interrupt!}:
        # that runs on the canceller's thread, which is not the thread the
        # scheduler was installed on.
        @queue = Queue.new
        inner = nil
        fiber = Fiber.schedule do
          inner = Fiber.current
          @scheduler = Fiber.scheduler
          begin
            ##
            # A held cancel is spent here, at the block's first instruction,
            # rather than raised in from the outside.
            #
            # **A raise into a fiber a scheduler owns does not deliver.** It
            # is not a resume: the scheduler is the one that transfers, and
            # what comes back through a foreign raise is the scheduler's own
            # pending exception - which a run of this repository's specs saw
            # as `Async::TimeoutError` arriving where `LLM::Interrupt` was
            # raised. The block is where a raise belongs, and the hook below
            # follows it the same way it follows a call.
            if @cancelled
              @delivered = true
              raise LLM::Interrupt
            end
            @queue << function.call
          rescue LLM::Interrupt, StandardError => ex
            ##
            # The interrupt is stored on the queue rather than raised on.
            # `LLM::Interrupt` is a subclass of `Exception`, and one that is
            # left to raise kills the scheduler's thread and takes the tasks
            # running on it with it - the caller reads the queue and raises
            # the interrupt on its own thread or fiber, and this task exits
            # silently.
            #
            # The rescue names the interrupt rather than leaving it to a bare
            # rescue, because a bare rescue - and `rescue => ex` - reaches
            # only `StandardError`.
            @queue << ex
            raise unless LLM::Interrupt === ex
          ensure
            ##
            # The hook runs on the fiber the call runs on, once the call has
            # ended, rather than on the thread that cancelled. See the note on
            # `LLM::Function::Thread::Task#spawn` for why it cannot run before
            # the call's frame has ended, and what `@delivered` means.
            function.interrupt! if @delivered
          end
        end
        @fiber = fiber || inner
        nil
      end
    end

    ##
    # @return [Boolean]
    def alive?
      @fiber&.alive? || false
    end

    ##
    # @return [nil]
    def interrupt!
      @cancelled = true
      if @fiber&.alive?
        @delivered = true
        ##
        # The scheduler is asked to raise when it knows how, and that is the
        # difference between a cancel and a cancel that never returns.
        #
        # `fiber_interrupt` schedules the raise and returns, which is what
        # `:async` uses for the same reason. A direct `Fiber#raise` on a
        # fiber the scheduler owns does not transfer the exception - it
        # suspends this thread, and this thread is the caller's, so the
        # interrupt reaches the tool and the canceller is left waiting
        # forever. The direct raise stays for a scheduler that has no such
        # hook.
        if @scheduler&.respond_to?(:fiber_interrupt)
          @scheduler.fiber_interrupt(@fiber, LLM::Interrupt.new)
        else
          @fiber.raise(LLM::Interrupt)
        end
      end
      nil
    end
    alias_method :cancel!, :interrupt!

    ##
    # Wait for the body to hand its result back.
    #
    # **It answers more than once.** `Queue#pop` takes the item, so the value
    # is kept rather than popped again, and a second wait is answered from
    # what the first one took - the same way `Thread#value` answers, and the
    # way `LLM::Function::Ractor::Task` is expected to.
    #
    # Anything that is an exception is raised rather than returned. An
    # interrupt is the usual one: a held cancel arrives here as the exception
    # the block ended with, and so does one raised at a call that was already
    # running.
    # @return [LLM::Function::Return]
    def wait
      return @guarded if @guarded
      spawn unless @fiber
      @result ||= @queue.pop
      raise @result if Exception === @result
      @result
    end
    alias_method :value, :wait

    ##
    # @return [Class]
    def group_class
      LLM::Function::Fiber::Group
    end
  end
end
