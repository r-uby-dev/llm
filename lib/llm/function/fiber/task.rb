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
  # A tool that implements `on_interrupt` is told on that fiber, once
  # the call has ended, rather than on the thread that cancelled it.
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
        # The scheduler is named inside the block and not read in
        # {#interrupt!}: that runs on the canceller's thread, which is not the
        # thread the scheduler was installed on.
        @queue = Queue.new
        fiber = Fiber.schedule do
          ##
          # The fiber names itself before it reads the record, so that a
          # cancel from another thread cannot fall between the two: it either
          # writes the record first, and this read spends it, or it finds a
          # fiber that is already named and hands the interrupt to the
          # scheduler. Naming itself afterwards would leave a body that is
          # running - and has already read the record - with no fiber for
          # {#interrupt!} to find.
          @fiber = Fiber.current
          @scheduler = Fiber.scheduler
          ##
          # The ending is held here so that the hook, and the queue below, are
          # the only two things that happen with it.
          outcome = begin
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
              function.call
            ensure
              ##
              # The hook runs on the fiber the call runs on, once the call has
              # ended, rather than on the thread that cancelled. See the note on
              # `LLM::Function::Thread::Task#spawn` for why it cannot run before
              # the call's frame has ended, and what `@delivered` means.
              function.interrupt! if @delivered
            end
          rescue => ex
            ##
            # Held rather than re-raised, and that includes an interrupt and an
            # error raised by the hook above. A body that leaves with an
            # exception ends the fiber from inside `Fiber.schedule`, so the
            # exception would leave {#spawn} rather than {#wait}: a group's
            # spawn would stop partway through its tasks, `@fiber` would be
            # left unset, and a later wait would spawn the body a second time.
            # The caller is given it from the queue instead, where the value
            # is.
            ex
          end
          ##
          # The ending is pushed after the hook has run, because the push is
          # what wakes a caller parked in {#wait} - and a hook that runs after
          # it is a hook the caller can race past, which is why
          # `LLM::Function::Async::Task` holds its result in a local until its
          # hook has run too.
          @queue << outcome
        end
        ##
        # The name the body set is the one that survives: `Fiber.schedule`
        # does not promise to return the fiber, and under `Async` it is nil for
        # a block that has already ended - which a body that ends on its first
        # instruction is.
        @fiber ||= fiber
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
        # `:async` uses for the same reason. A direct `Fiber#raise` on a fiber
        # the scheduler owns does not transfer the exception - it suspends
        # this thread, and this thread is the caller's, so the interrupt
        # reaches the tool and the canceller is left waiting forever. The
        # direct raise stays for a scheduler that has no such hook.
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
    # is kept rather than popped again, and a second wait is answered from what
    # the first one took - the same way `Thread#value` answers, and the way
    # `LLM::Function::Ractor::Task` is expected to.
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
