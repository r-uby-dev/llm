# frozen_string_literal: true

module LLM::Function::Sequential
  ##
  # Wraps an array of {LLM::Function::Sequential::Task} objects
  # for sequential execution. Provides the same interface as
  # concurrent group wrappers so callers can flow through
  # `task(strategy).wait` regardless of the strategy being
  # used.
  class Group < LLM::Function::Group
    ##
    # @param [Array<LLM::Function::Sequential::Task>] tasks
    #  One or more Sequential::Task objects
    # @return [LLM::Function::Sequential::Group]
    def initialize(tasks)
      @tasks = tasks
      @owner = nil
    end

    ##
    # @return [nil]
    def spawn
      # no-op (execution happens in wait)
      @tasks.each(&:spawn)
      nil
    ensure
      @spawned = true
    end

    ##
    # @return [Boolean]
    def alive?
      @tasks.any?(&:alive?)
    end

    ##
    # Interrupts the thread blocked in {#wait}, and tells the tasks.
    #
    # Sequential functions run on the caller's thread, so the raise is what
    # interrupts the call and it has to land there. It is issued first, and
    # the tasks are told second: the delivery is this group's whole
    # interrupt, and a hook that raises must not be able to take it with it
    # or to leave the remaining tasks untold. That is also the order the
    # in-process strategies use, where the hook runs after the raise.
    # @return [nil]
    def interrupt!
      @owner&.raise(LLM::Interrupt)
      @tasks.each(&:interrupt!)
      nil
    end
    alias_method :cancel!, :interrupt!

    ##
    # @see LLM::Function::Group#wait
    # @return [Array<LLM::Function::Return>]
    def wait
      @owner = Thread.current
      super
    ensure
      @owner = nil
    end
    alias_method :value, :wait
  end
end
