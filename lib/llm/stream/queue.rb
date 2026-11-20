# frozen_string_literal: true

class LLM::Stream
  ##
  # A small queue for collecting streamed tool work. Values can be immediate
  # {LLM::Function::Return} objects or concurrent handles returned by
  # {LLM::Function#spawn}. Calling {#wait} resolves queued work and
  # returns an array of {LLM::Function::Return} values.
  class Queue
    ##
    # @param [LLM::Stream] stream
    # @return [LLM::Stream::Queue]
    def initialize(stream)
      @stream = stream
      @items = []
    end

    ##
    # Enqueue a function return or spawned task.
    # @param [LLM::Function::Return, Thread, Async::Task, Fiber] item
    # @return [LLM::Stream::Queue]
    def <<(item)
      @items << item
      self
    end

    ##
    # Returns true when the queue is empty.
    # @return [Boolean]
    def empty?
      @items.empty?
    end

    ##
    # @return [nil]
    def interrupt!
      @items.each(&:interrupt!)
      nil
    end
    alias_method :cancel!, :interrupt!

    ##
    # Waits for queued work to finish and returns function results.
    #
    # Queued work is waited according to the actual task types that were
    # enqueued, so callers do not need to provide a strategy here.
    #
    # @return [Array<LLM::Function::Return>]
    def wait
      returns, tasks = @items.shift(@items.length).partition { LLM::Function::Return === _1 }
      tasks.each do |task|
        task.on_return = ->(val) { @stream&.on_tool_return(task.function, val) }
      end
      returns.concat wait_tasks(tasks)
    end
    alias_method :value, :wait

    private

    def wait_tasks(tasks)
      return [] if tasks.empty?
      results = {}
      grouped_tasks = tasks.group_by(&:group_class)
      grouped_tasks.each do |group_class, group|
        returns = group_class.new(group).wait
        returns.each.with_index { results[group[_2]] = _1 }
      end
      tasks.map { results[_1] }
    end

  end
end
