# frozen_string_literal: true

class LLM::Function
  ##
  # The {LLM::Function::ThreadGroup} class wraps an array of
  # `Thread` objects that are running {LLM::Function} calls
  # concurrently. It provides a single {#wait} method that
  # collects the {LLM::Function::Return} values from those
  # threads.
  #
  # This class is returned by {LLM::Function::Array#spawn}
  # when you call `ctx.functions.spawn` on the collection
  # returned by {LLM::Context#functions}. It is a lightweight
  # wrapper that does not inherit from Ruby's built-in
  # {::ThreadGroup}.
  #
  # @example
  #   llm = LLM.openai(key: ENV["KEY"])
  #   ctx = LLM::Context.new(llm, tools: [Weather, News, Stocks])
  #   ctx.talk "Summarize the weather, headlines, and stock price."
  #   grp = ctx.functions.spawn
  #   # do other work while tools run...
  #   ctx.talk(grp.wait)
  #
  # @see LLM::Function::Array#spawn
  # @see LLM::Function::Array#wait
  class ThreadGroup
    ##
    # Creates a new {LLM::Function::ThreadGroup} from an array
    # of `Thread` objects.
    #
    # @param [Array<Thread>] threads
    #   An array of threads, each running an {LLM::Function#spawn}
    #   call. The thread's `Thread#value` will be an
    #   {LLM::Function::Return}.
    #
    # @return [LLM::Function::ThreadGroup]
    #   Returns a new thread group.
    def initialize(threads)
      @threads = threads
    end

    ##
    # Returns whether any thread in the group is still alive.
    #
    # This method checks if any of the threads in the group are
    # still running. It can be useful for monitoring concurrent
    # tool execution without blocking.
    #
    # @example
    #   llm = LLM.openai(key: ENV["KEY"])
    #   ctx = LLM::Context.new(llm, tools: [Weather, News, Stocks])
    #   ctx.talk "Summarize the weather, headlines, and stock price."
    #   grp = ctx.functions.spawn
    #   while grp.alive?
    #     puts "Tools are still running..."
    #     sleep 1
    #   end
    #   ctx.talk(grp.wait)
    #
    # @return [Boolean]
    #   Returns true if any thread in the group is still alive,
    #   false otherwise.
    def alive?
      @threads.any?(&:alive?)
    end

    ##
    # @return [nil]
    def interrupt!
      @threads.each(&:interrupt!)
      nil
    end
    alias_method :cancel!, :interrupt!

    ##
    # Waits for all threads in the group to finish and returns
    # their {LLM::Function::Return} values.
    #
    # This method blocks until every thread in the group has
    # completed. If a thread raised an exception, the exception
    # is caught and wrapped in an {LLM::Function::Return} with
    # error information.
    #
    # @example
    #   llm = LLM.openai(key: ENV["KEY"])
    #   ctx = LLM::Context.new(llm, tools: [Weather, News, Stocks])
    #   ctx.talk "Summarize the weather, headlines, and stock price."
    #   grp = ctx.functions.spawn
    #   returns = grp.wait
    #   # returns is now an array of LLM::Function::Return objects
    #   ctx.talk(returns)
    #
    # @return [Array<LLM::Function::Return>]
    #   Returns an array of function return values, in the same
    #   order as the original threads.
    def wait
      @threads.map(&:value)
    end
    alias_method :value, :wait
  end
end
