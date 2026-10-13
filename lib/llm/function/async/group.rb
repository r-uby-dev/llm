# frozen_string_literal: true

module LLM::Function::Async
  ##
  # Wraps an array of {Async::Task} objects running on a shared
  # {LLM::Function::Async::Reactor}. The reactor is created on
  # demand if not provided.
  class Group < LLM::Function::Group
    ##
    # @param [Array<Async::Task>] tasks
    # @param [Hash] options
    # @option options [LLM::Function::Async::Reactor] :reactor
    def initialize(tasks, options = {})
      @tasks = tasks
      @reactor = options[:reactor] || LLM::Function::Async::Reactor.new
    end

    ##
    # @return [nil]
    def spawn
      @tasks.each do |task|
        task.reactor = @reactor
        task.spawn
      end
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
    # @see LLM::Function::Group#wait
    # @return [Array<LLM::Function::Return>]
    def wait
      super
    ensure
      @reactor.stop
    end
    alias_method :value, :wait
  end
end
