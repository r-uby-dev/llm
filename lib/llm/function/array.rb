# frozen_string_literal: true

class LLM::Function
  ##
  # The {LLM::Function::Array} module extends the array
  # returned by {LLM::Context#pending_functions} with methods
  # that can call all pending functions sequentially or
  # concurrently. The return values can be reported back
  # to the LLM on the next turn.
  module Array
    ##
    # Calls all functions in a collection sequentially.
    #
    # @return [Array<LLM::Function::Return>]
    #  Returns values to be reported back to the LLM.
    def call
      task(:sequential).wait
    end

    ##
    # Calls all functions in a collection concurrently.
    # This method returns an execution group that can be
    # waited on to access the return values.
    #
    # @param [Symbol] strategy
    #   Controls concurrency strategy:
    #   - `:sequential`: Call functions sequentially without spawning
    #   - `:thread`: Use threads
    #   - `:async`: Use async tasks (requires async gem)
    #   - `:fiber`: Use scheduler-backed fibers (requires Fiber.scheduler)
    #   - `:fork`: Use forked child processes
    #   - `:ractor`: Use Ruby ractors (class-based tools only; MCP tools are not supported)
    #
    # @return [LLM::Function::Sequential::Group, LLM::Function::Thread::Group, LLM::Function::Async::Group, LLM::Function::Fiber::Group, LLM::Function::Fork::Group, LLM::Function::Ractor::Group]
    def task(strategy)
      case strategy
      when :sequential
        Sequential::Group.new(map { _1.task(:sequential) })
      when :async
        LLM.require "async" unless defined?(::Async)
        Async::Group.new(map { |fn| fn.task(:async) })
      when :thread
        Thread::Group.new(map { |fn| fn.task(:thread) })
      when :fiber
        Fiber::Group.new(map { |fn| fn.task(:fiber) })
      when :fork
        Fork::Group.new(map { |fn| fn.task(:fork) })
      when :ractor
        Ractor::Group.new(map { |fn| fn.task(:ractor) })
      else
        raise ArgumentError, "Unknown strategy: #{strategy.inspect}. Expected :sequential, :thread, :async, :fiber, :fork, or :ractor"
      end
    end

    ##
    # Calls all functions in a collection concurrently
    # and waits for the return values.
    #
    # @param [Symbol] strategy
    #   Controls concurrency strategy:
    #   - `:sequential`: Call functions sequentially without spawning
    #   - `:thread`: Use threads
    #   - `:async`: Use async tasks (requires async gem)
    #   - `:fiber`: Use scheduler-backed fibers (requires Fiber.scheduler)
    #   - `:fork`: Use forked child processes
    #   - `:ractor`: Use Ruby ractors (class-based tools only; MCP tools are not supported)
    #
    # @return [Array<LLM::Function::Return>]
    #  Returns values to be reported back to the LLM.
    def wait(strategy)
      task(strategy).wait
    end

    ##
    # @return [LLM::Function::Array]
    def -(other)
      super.extend(Array)
    end
  end
end
