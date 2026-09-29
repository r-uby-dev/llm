# frozen_string_literal: true

module LLM::Function::Async
  ##
  # {LLM::Function::Async::Task} wraps a function call in an
  # {Async::Task} running on a shared
  # {LLM::Function::Async::Reactor}. The task is spawned lazily
  # in {#wait} or explicitly in {#spawn}.
  #
  # Work is submitted to the reactor through its inbox queue.
  # Results are bridged back through the task's own queue.
  class Task < LLM::Function::Task
    ##
    # @param [LLM::Function] fn
    # @param [Hash] options
    # @option options [LLM::Function::Async::Reactor] :reactor
    def initialize(fn, options = {})
      super
      @reactor = options[:reactor]
    end

    ##
    # Assign the reactor. Used when a task is created before its
    # reactor is available.
    # @param [LLM::Function::Async::Reactor] reactor
    def reactor=(reactor)
      @reactor = reactor
    end

    ##
    # Submit the function call to the reactor. The result is
    # pushed to a queue that {#wait} consumes.
    #
    # The task names itself and its scheduler from inside the reactor,
    # because neither is reachable from anywhere else: `#interrupt!` runs
    # on the caller's thread, and `Async::Task.current` is the task of the
    # *current* fiber.
    #
    # A cancel can arrive before this block has run. The tool is not
    # started then, and the caller has already been told, so the block
    # answers instead of running anything.
    # @return [nil]
    def spawn
      return if @guarded
      @queue = Queue.new
      @alive = true
      @reactor.submit do
        @task = Async::Task.current
        @scheduler = Fiber.scheduler
        raise LLM::Interrupt if @cancelled
        @queue << function.call
      rescue LLM::Interrupt => e
        @queue << e
        raise
      end
      nil
    end

    ##
    # @return [Boolean]
    def alive?
      @alive || false
    end

    ##
    # Tells the tool, and lets it answer.
    #
    # A running tool is the one the interrupt belongs to: it handles it, or
    # it lets it raise, and either way the block above is what the caller
    # hears from - its value, or the exception it forwards. The sentinel is
    # only for the one case that has no tool to answer: a cancel that
    # arrived before the task started, where there is nothing to raise on
    # and the caller must not wait for a block that will not run.
    #
    # The fiber is checked before it is raised on because a finished task
    # has none - `Async::Task#finish!` clears it - and the scheduler does
    # not accept nil. A task that has already returned is a no-op, which is
    # what `LLM::Function::Return#interrupt!` says one is.
    # @return [nil]
    def interrupt!
      @alive = false
      @cancelled = true
      if @task&.fiber&.alive?
        @scheduler.fiber_interrupt(@task.fiber, LLM::Interrupt.new)
      elsif @task.nil?
        @queue << LLM::Interrupt.new
      end
      ##
      # A reactor with nothing to do is a thread parked on an inbox for the
      # life of the process, so the cancel stops it too - which is what a
      # group's `wait` already does, and what a task waited on outside one
      # otherwise never gets.
      @reactor&.stop
      nil
    end
    alias_method :cancel!, :interrupt!

    ##
    # Wait for the result queue to contain a value.
    # @return [LLM::Function::Return]
    def wait
      return @guarded if @guarded
      spawn unless @queue
      result = @queue.pop
      @alive = false
      raise result if LLM::Interrupt === result
      result
    end
    alias_method :value, :wait

    ##
    # @return [Class]
    def group_class
      LLM::Function::Async::Group
    end
  end
end
