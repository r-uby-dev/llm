# frozen_string_literal: true

module LLM::Function::Thread
  ##
  # Wraps an array of {Thread::Task} objects for concurrent
  # thread-based execution. Interrupts all tasks and waits
  # for them to complete.
  class Group < LLM::Function::Group
    ##
    # @param [Array<LLM::Function::Thread::Task>] tasks
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
    # @return [Array<LLM::Function::Return>]
    def wait
      spawn unless @spawned
      interrupt = nil
      vals = @tasks.map do |task|
        val = task.wait
        if LLM::Interrupt === val
          interrupt = val
          task.tracer&.on_tool_interrupt(ex: val, span: task.span)
        elsif Exception === val
          task.tracer&.on_tool_error(ex: val, span: task.span)
        else
          task.tracer&.on_tool_finish(result: val, span: task.span)
          val
        end
      end
      interrupt ? raise(interrupt) : vals
    end
    alias_method :value, :wait
  end
end
