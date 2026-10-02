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
  # is held rather than dropped, and spent inside the call: the
  # tool is entered, so a tool whose own `rescue` cleans up is
  # cleaned up by a cancel that arrived before it started, the
  # way it is on `:thread`, `:fork` and `:ractor`.
  #
  # **The scheduler must implement `fiber_interrupt`**, which is how a raise
  # is asked for from the call's own fiber rather than issued before it.
  # Without it a cancel that arrived early could only be delivered before the
  # call, so the strategy refuses at {#spawn} - in the caller's hands, before
  # a fiber exists - rather than inside one, where the refusal would be an
  # unhandled exception and a caller waiting on a queue nothing fills.
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
      elsif !Fiber.scheduler.respond_to?(:fiber_interrupt)
        ##
        # Refused here rather than at the window, which is built inside the
        # fiber: a raise in there is an exception the fiber ends with, and
        # the caller waits on a queue that will never fill.
        raise LLM::FiberError,
          "this scheduler does not implement fiber_interrupt, so a cancel " \
          "cannot be held until the tool starts: it would be delivered " \
          "before the call, and the tool would never run"
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
          @window = LLM::Function::Window.new(scheduler: @scheduler, fiber: inner)
          ##
          # **A cancel that arrived before this fiber ran is held by the
          # window.** There is nothing to ask for yet, so the ask is
          # recorded and issued when the call opens - which is the
          # transition the window alerts, and the only place that can, since
          # this fiber is the one that will be running the tool.
          #
          # A canceller cannot wait for that here, which is the difference
          # from `:thread`: it may be the fiber running the tool, so a
          # canceller that waited would be waiting on the fiber it means to
          # interrupt. `wait: false` is the only shape this strategy can
          # take, and the deferred ask is what makes it work.
          @window.interrupt!(wait: false) if @cancelled
          begin
            ##
            # The call opens here, and it is what a deferred ask is issued
            # against. The tool is entered, which is what a held cancel used
            # to prevent - this fiber raised before the call was reached, so
            # the tool's own `rescue` never saw the interrupt.
            @window.running!
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
            # The tool has answered, so a cancel that arrives from here on
            # asks nothing - which is the no-op a cancel that arrives once
            # the call has returned is.
            @window.finished!
            ##
            # The hook runs on the fiber the call runs on, once the call has
            # ended, rather than on the thread that cancelled. See the note on
            # `LLM::Function::Thread::Task#spawn` for why it cannot run before
            # the call's frame has ended, and what the window's
            # `interrupted?` means.
            function.interrupt! if @window.interrupted?
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
    # Tells the tool, and lets it answer.
    #
    # **The ask is the window's, and it does not wait.** This runs on the
    # canceller's thread, which can be the thread the scheduler runs on, so
    # a canceller that waited for the call to start would block the fiber it
    # means to interrupt. A call that is running is asked about at once, one
    # that has finished asks nothing, and one that has not opened holds the
    # ask until it does.
    #
    # Whether waiting would have been affordable is the window's to say, not
    # this task's: `fiber_interrupt` schedules the raise and returns, where
    # a direct raise on a fiber a scheduler owns suspends the caller until
    # the scheduler delivers it.
    # @return [nil]
    def interrupt!
      @cancelled = true
      @window&.interrupt!(wait: false)
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
