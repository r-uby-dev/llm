# frozen_string_literal: true

module LLM::Function::Ractor
  ##
  # Wraps an array of {Ractor::Task} objects that are running
  # {LLM::Function} calls concurrently.
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
    # @raise [LLM::Interrupt]
    #  When one or more tool calls were interrupted
    # @return [Array<LLM::Function::Return>]
    ##
    # @see LLM::Function::Group#wait
    # @note The cookie judgement is not here any more: the task that
    #  reads the mailbox is what knows whether a message names its own
    #  call, so it answers with an {LLM::Interrupt} when it does and the
    #  shared wait reports it.
    # @return [Array<LLM::Function::Return>]
    def wait
      super
    end
    alias_method :value, :wait
  end
end
