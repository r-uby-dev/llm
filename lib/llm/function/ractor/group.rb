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
    def wait
      spawn unless @spawned
      interrupt, results = nil, []
      @tasks.each do |task|
        result = task.wait
        if result.value[:interrupt] and result.value[:cookie] == task.cookie
          interrupt = LLM::Interrupt.new
          task.tracer&.on_tool_interrupt(ex: interrupt, span: task.span)
        else
          results << result
        end
      end
      interrupt ? raise(interrupt) : results
    end
    alias_method :value, :wait
  end
end
