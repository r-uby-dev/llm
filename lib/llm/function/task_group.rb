# frozen_string_literal: true

class LLM::Function
  ##
  # The {LLM::Function::TaskGroup} class wraps an array of
  # `Async::Task` objects that are running {LLM::Function} calls
  # concurrently using the async gem.
  #
  # This class provides the same interface as {LLM::Function::ThreadGroup}
  # but uses async tasks for lightweight concurrency with automatic
  # scheduling and I/O management.
  #
  # @example
  #   llm = LLM.openai(key: ENV["KEY"])
  #   ctx = LLM::Context.new(llm, tools: [Weather, News, Stocks])
  #   ctx.talk "Summarize the weather, headlines, and stock price."
  #   grp = ctx.functions.spawn(:task)
  #   # do other work while tools run...
  #   ctx.talk(grp.wait)
  #
  # @see LLM::Function::Array#spawn
  # @see LLM::Function::ThreadGroup
  # @see LLM::Function::FiberGroup
  class TaskGroup
    ##
    # Creates a new {LLM::Function::TaskGroup} from an array
    # of async task objects.
    #
    # @param [Array<Async::Task>] tasks
    #   An array of async tasks, each running an `LLM::Function#spawn_async` call.
    #
    # @return [LLM::Function::TaskGroup]
    #   Returns a new task group.
    def initialize(tasks)
      @tasks = tasks
    end

    ##
    # Returns whether any task in the group is still alive.
    #
    # This method checks if any of the tasks in the group are
    # still running. It can be useful for monitoring concurrent
    # tool execution without blocking.
    #
    # @example
    #   llm = LLM.openai(key: ENV["KEY"])
    #   ctx = LLM::Context.new(llm, tools: [Weather, News, Stocks])
    #   ctx.talk "Summarize the weather, headlines, and stock price."
    #   grp = ctx.functions.spawn(:task)
    #   while grp.alive?
    #     puts "Tools are still running..."
    #     sleep 1
    #   end
    #   ctx.talk(grp.wait)
    #
    # @return [Boolean]
    #   Returns true if any task in the group is still alive,
    #   false otherwise.
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
    # Waits for all tasks in the group to finish and returns
    # their {LLM::Function::Return} values.
    #
    # This method blocks until every task in the group has
    # completed. If a task raised an exception, the exception
    # is caught and wrapped in an {LLM::Function::Return} with
    # error information.
    #
    # @example
    #   llm = LLM.openai(key: ENV["KEY"])
    #   ctx = LLM::Context.new(llm, tools: [Weather, News, Stocks])
    #   ctx.talk "Summarize the weather, headlines, and stock price."
    #   grp = ctx.functions.spawn(:task)
    #   returns = grp.wait
    #   # returns is now an array of LLM::Function::Return objects
    #   ctx.talk(returns)
    #
    # @return [Array<LLM::Function::Return>]
    #   Returns an array of function return values, in the same
    #   order as the original tasks.
    def wait
      @tasks.map(&:wait)
    end
    alias_method :value, :wait
  end
end
