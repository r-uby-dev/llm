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
  # is held rather than dropped, and delivered when it does.
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
          function.call
        ensure
          ##
          # The hook runs on the fiber the call runs on, once the call has
          # ended, rather than on the thread that cancelled. See the note on
          # `LLM::Function::Thread::Task#spawn` for why it cannot run before
          # the call's frame has ended, and what `@delivered` means.
          function.interrupt! if @delivered
        end
        deliver!
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

    private

    ##
    # Spends a cancel that was held rather than dropped.
    #
    # A cancel that arrives before the fiber exists has nothing to be
    # raised on, so it is recorded, and this is where it is delivered.
    # `Fiber.schedule` runs the block before it returns, so the call is
    # live by the time this runs - it has started, and is suspended
    # somewhere inside itself - and the raise lands inside the call rather
    # than at its edge. A fiber whose call has already returned is left
    # alone, which is the cancel that arrives too late to be anything but a
    # no-op.
    # @return [nil]
    def deliver!
      if @cancelled && @fiber&.alive?
        @delivered = true
        @fiber.raise(LLM::Interrupt)
      end
      nil
    end
  end
end
