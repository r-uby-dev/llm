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
        @fiber = Fiber.schedule do
          ##
          # The fiber names itself first, because the assignment below
          # never happens if the block raises - and a held cancel raises
          # here rather than at the call.
          @fiber = Fiber.current
          ##
          # A held cancel is spent here, at the block's first instruction,
          # rather than raised in from the outside.
          #
          # **A raise into a fiber a scheduler owns does not deliver.** It
          # is not a resume: the scheduler is the one that transfers, and
          # what comes back through a foreign raise is the scheduler's own
          # pending exception - which a spec in this repository saw as
          # `Async::TimeoutError` arriving where `LLM::Interrupt` was
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
