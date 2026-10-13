# frozen_string_literal: true

module LLM::Function::Fork
  ##
  # Wraps an array of {Fork::Task} objects that are running
  # in forked child processes.
  class Group < LLM::Function::Group
    ##
    # @param [Array<LLM::Function::Task>] tasks
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
