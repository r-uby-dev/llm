# frozen_string_literal: true

module LLM::Function::Sequential
  ##
  # The {LLM::Function::Sequential::Task} class wraps a single
  # direct function call behind the same task-like interface
  # used by spawned concurrency modes.
  class Task < LLM::Function::Task
    ##
    # @return [nil]
    def spawn
      # no-op (execution happens in wait)
    end

    ##
    # @return [Boolean]
    def alive?
      false
    end

    ##
    # @return [nil]
    def interrupt!
      function.interrupt!
      nil
    end
    alias_method :cancel!, :interrupt!

    ##
    # @return [LLM::Function::Return]
    def wait
      @result = @result ? @result : begin
        @started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        @result = LLM::Object.from(unbox: @intercepted || function.call)
        @finished_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        @result
      end
      @result&.unbox
    end
    alias_method :value, :wait

    ##
    # @return [Class]
    def group_class
      LLM::Function::Sequential::Group
    end
  end
end
