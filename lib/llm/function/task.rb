# frozen_string_literal: true

class LLM::Function
  ##
  # This class is the superclass that all concurrency
  # strategies must subclass in order to implement their
  # own Task class. It provides a common interface that
  # is the same across all concurrency strategies.
  class Task
    ##
    # @return [LLM::Function]
    attr_reader :function

    ##
    # The tracer for the task
    # @return [LLM::Tracer, nil]
    attr_reader :tracer

    ##
    # The span returned by {LLM::Tracer#on_tool_start}
    # @return [Object]
    attr_reader :span

    ##
    # Returns when a task started, or nil
    # @note
    #  This method captures a monotonic clock
    #  time (Process::CLOCK_MONOTONIC) rather
    #  than a Time object.
    # @return [Float, nil]
    attr_reader :started_at

    ##
    # Returns when a task finished, or nil
    # @note
    #  This method captures a monotonic clock
    #  time (Process::CLOCK_MONOTONIC) rather
    #  than a Time object.
    # @return [Float, nil]
    attr_reader :finished_at

    ##
    # @param [LLM::Function] fn
    # @param [Hash] options
    #  An optional set of options that are specific
    #  to a given concurrency strategy.
    # @option options [LLM::Function::Return, nil] :guarded
    #  A blocked return produced by the function's guard, or the in-band
    #  error for a tool that cannot be built. When set, the task yields it
    #  without running the tool.
    def initialize(fn, options = {})
      @function = fn
      @guarded = options[:guarded]
      @tracer = options[:tracer]
      @finished_at = nil
    end

    ##
    # @abstract
    # @return [nil]
    def spawn
      raise NotImplementedError
    end

    ##
    # @abstract
    # @return [Boolean]
    def alive?
      raise NotImplementedError
    end

    ##
    # @abstract
    # @return [nil]
    def interrupt!
      raise NotImplementedError
    end
    alias_method :cancel!, :interrupt!

    ##
    # This method returns an instance of
    # {LLM::Function::Return} or {LLM::Interrupt}
    # when the task has received an interrupt.
    #
    # An exception that occurs inside a tool is
    # rescued, and returned by this method as a
    # {LLM::Function::Return} object. It can be
    # distinguished from other returns through
    # the {LLM::Function::Return#error?} method.
    #
    # @abstract
    # @return [LLM::Function::Return, LLM::Interrupt]
    def wait
      raise NotImplementedError
    end
    alias_method :value, :wait

    ##
    # @abstract
    # @return [Class]
    def group_class
      raise NotImplementedError
    end
  end
end
