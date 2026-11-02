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
      @span = @tracer&.on_tool_start(
        id: function.id,
        name: function.name,
        arguments: function.arguments,
        model: function.model
      )
      nil
    end

    ##
    # @return [Boolean]
    def alive?
      false
    end

    ##
    # @return [nil]
    def interrupt!
      @cancelled = true
      function.interrupt!
      nil
    end
    alias_method :cancel!, :interrupt!

    ##
    # @return [LLM::Function::Return, LLM::Interrupt]
    def wait
      return @intercepted if intercepted?
      if @cancelled && !@result
        @started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        @finished_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        @result = LLM::Interrupt.new
      end
      @result = @result ? @result : begin
        @started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        begin
          @result = LLM::Object.from(unbox: function.call)
        rescue LLM::Interrupt => ex
          @result = LLM::Object.from(unbox: ex)
        ensure
          @finished_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        end
        @result
      end
      @result.is_a?(LLM::Interrupt) ? @result : @result&.unbox
    end
    alias_method :value, :wait

    ##
    # @return [Class]
    def group_class
      LLM::Function::Sequential::Group
    end
  end
end
