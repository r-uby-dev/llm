# frozen_string_literal: true

module LLM::Function::Fiber
  ##
  # Wraps an array of {Fiber::Task} objects for cooperative
  # concurrent execution. Interrupts all tasks and waits
  # for them to complete.
  class Group < LLM::Function::Group
    ##
    # @param [Array<LLM::Function::Fiber::Task>] tasks
    def initialize(tasks)
      @tasks = tasks
    end

    ##
    # @return [nil]
    def spawn
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
    # @return [nil]
    def interrupt!
      @tasks.each(&:interrupt!)
      nil
    end
    alias_method :cancel!, :interrupt!

    ##
    # @see LLM::Function::Group#wait
    # @return [Array<LLM::Function::Return>]
    def wait
      super
    end
    alias_method :value, :wait
  end
end
