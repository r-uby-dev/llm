# frozen_string_literal: true

class LLM::Function
  ##
  # The {LLM::Function::FiberGroup} class wraps an array of
  # `Fiber` objects that are running {LLM::Function} calls
  # concurrently using scheduler-backed fibers.
  #
  # This class provides the same interface as {LLM::Function::ThreadGroup}
  # but uses scheduler-backed fibers for cooperative concurrency.
  #
  # @example
  #   llm = LLM.openai(key: ENV["KEY"])
  #   ctx = LLM::Context.new(llm, tools: [Weather, News, Stocks])
  #   ctx.talk "Summarize the weather, headlines, and stock price."
  #   grp = ctx.functions.spawn(:fiber)
  #   # do other work while tools run...
  #   ctx.talk(grp.wait)
  #
  # @see LLM::Function::Array#spawn
  # @see LLM::Function::ThreadGroup
  # @see LLM::Function::TaskGroup
  class FiberGroup
    ##
    # Creates a new {LLM::Function::FiberGroup} from an array
    # of fiber objects.
    #
    # @param [Array<Fiber>] fibers
    #   An array of fibers, each running an `LLM::Function#spawn_fiber` call.
    #
    # @return [LLM::Function::FiberGroup]
    #   Returns a new fiber group.
    def initialize(fibers)
      @fibers = fibers
    end

    ##
    # Returns whether any fiber in the group is still alive.
    #
    # This method checks if any of the fibers in the group are
    # still running. It can be useful for monitoring concurrent
    # tool execution without blocking.
    #
    # @example
    #   llm = LLM.openai(key: ENV["KEY"])
    #   ctx = LLM::Context.new(llm, tools: [Weather, News, Stocks])
    #   ctx.talk "Summarize the weather, headlines, and stock price."
    #   grp = ctx.functions.spawn(:fiber)
    #   while grp.alive?
    #     puts "Tools are still running..."
    #     sleep 1
    #   end
    #   ctx.talk(grp.wait)
    #
    # @return [Boolean]
    #   Returns true if any fiber in the group is still alive,
    #   false otherwise.
    def alive?
      @fibers.any?(&:alive?)
    end

    ##
    # @return [nil]
    def interrupt!
      @fibers.each(&:interrupt!)
      nil
    end
    alias_method :cancel!, :interrupt!

    ##
    # Waits for all fibers in the group to finish and returns
    # their {LLM::Function::Return} values.
    #
    # This method blocks until every fiber in the group has
    # completed. If a fiber raised an exception, the exception
    # is caught and wrapped in an {LLM::Function::Return} with
    # error information.
    #
    # @example
    #   llm = LLM.openai(key: ENV["KEY"])
    #   ctx = LLM::Context.new(llm, tools: [Weather, News, Stocks])
    #   ctx.talk "Summarize the weather, headlines, and stock price."
    #   grp = ctx.functions.spawn(:fiber)
    #   returns = grp.wait
    #   # returns is now an array of LLM::Function::Return objects
    #   ctx.talk(returns)
    #
    # @return [Array<LLM::Function::Return>]
    #   Returns an array of function return values, in the same
    #   order as the original fibers.
    def wait
      @fibers.map do |fiber|
        fiber.alive? ? scheduler.run : nil
        fiber.value
      end
    end
    alias_method :value, :wait

    private

    def scheduler
      Fiber.scheduler
    end
  end
end
