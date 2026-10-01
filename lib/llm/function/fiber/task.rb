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
        # The body records its own ending, because the fiber is not always
        # askable afterwards.
        #
        # `Fiber.schedule` does not promise to return the fiber: under
        # `Async` it is nil for a block that has already ended, and a block
        # that raises on its first instruction - a held cancel - is exactly
        # that. So the fiber names itself, and `@fiber` is the scheduler's
        # return when there is one and that name when there is not.
        #
        # The result and the failure are recorded here as well, because a
        # fiber that has ended cannot be asked for either: `Fiber#value` is
        # not a method, and a value read off a dead body is a `FiberError`.
        # `#wait` reads what this block wrote, and only falls back to
        # `@fiber` while the call is still in flight - which is the one case
        # where there is something to wait on.
        inner = nil
        fiber = Fiber.schedule do
          inner = Fiber.current
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
            @result = function.call
          rescue => ex
            @failure = ex
            raise
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
        @fiber.raise(LLM::Interrupt)
      end
      nil
    end
    alias_method :cancel!, :interrupt!

    ##
    # @return [LLM::Function::Return]
    def wait
      return @guarded if @guarded
      spawn unless @fiber
      raise @failure if @failure
      @result ||= @fiber.value
    end
    alias_method :value, :wait

    ##
    # @return [Class]
    def group_class
      LLM::Function::Fiber::Group
    end
  end
end
