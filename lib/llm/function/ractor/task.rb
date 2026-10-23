# frozen_string_literal: true

class LLM::Function
  ##
  # The {LLM::Function::Ractor::Task} class wraps a ractor-backed
  # function call.
  #
  # **One ractor, not two.** The ractor a task spawns runs the tool
  # itself and hands its result to a {Ractor::Port} the task reads.
  # There is no second ractor to supervise the first: a watcher thread
  # inside the ractor services interrupts, and the port is the one
  # place a result leaves by.
  class Ractor::Task < LLM::Function::Task
    ##
    # @api private
    Ractor = ::Ractor
    private_constant :Ractor

    ##
    # @return [Ractor::Port]
    #  The port the result is delivered to
    attr_reader :port

    ##
    # @return [LLM::Tracer, nil]
    attr_reader :tracer

    ##
    # @return [String]
    attr_reader :cookie

    ##
    # @return [Object]
    attr_reader :span

    ##
    # @param [LLM::Function] fn
    # @param [Hash] options
    # @option options [LLM::Tracer, nil] :tracer
    # @option options [Class] :runner_class
    # @option options [String, nil] :id
    # @option options [String] :name
    # @option options [Hash, Array, nil] :arguments
    # @option options [String, nil] :model
    # @return [LLM::Function::Ractor::Task]
    def initialize(fn, options = {})
      super
      @runner_class = options.fetch(:runner_class)
      @id = options.fetch(:id)
      @name = options.fetch(:name)
      @arguments = options.fetch(:arguments)
      @model = options.fetch(:model, nil)
      @cancelled = false
      @cookie = SecureRandom.hex
    end

    ##
    # @return [LLM::Function::Ractor::Task]
    def spawn
      @span = @tracer&.on_tool_start(
        id: @id, name: @name,
        arguments: @arguments, model: @model
      )
      return if intercepted?
      @port = Ractor::Port.new
      @exits = Ractor::Port.new
      @ractor = build_task(@port)
      @ractor.monitor(@exits)
      watch_exit
      if @cancelled
        @cancelled = false
        interrupt!
      end
      self
    end

    ##
    # A task that has been waited on is not alive, and it answers that
    # from the result it holds rather than by asking a ractor that has
    # gone with the answering of the wait.
    #
    # Before then it is alive for as long as its ractor is, which is
    # what the monitor port says: the ractor sends `:exited` when it
    # ends, and it ends only after the result has been handed over.
    # @return [Boolean]
    def alive?
      return false if @result
      @ractor ? !@exited : false
    end

    ##
    # Tells the tool to stop.
    #
    # **A cancel that arrives before `spawn` is remembered, not lost.**
    # The ractor is built in `spawn`, and there is no safe navigation to
    # a message that has not been sent: a cancel that answered `nil` here
    # was a cancel that said nothing, and the call ran as if nobody had
    # asked it to stop. It is delivered by `spawn` instead, which is the
    # first moment there is anything to deliver it to.
    # @return [nil]
    def interrupt!
      if @ractor
        @ractor.send(:interrupt)
      else
        @cancelled = true
      end
      nil
    rescue ::Ractor::ClosedError
      nil
    end
    alias_method :cancel!, :interrupt!

    ##
    # The first wait is answered by the port the ractor delivered its
    # result to, which holds it whether or not the ractor is still
    # there. Every wait after that is answered from memory, the way
    # {LLM::Function::Thread::Task#wait} answers from the thread's value.
    # @return [LLM::Function::Return]
    def wait
      return @intercepted if intercepted?
      @result ||= begin
        spawn unless @port
        _, id, name, value, @finished_at = @port.receive.first(5)
        if Hash === value and value[:interrupt] and value[:cookie] == @cookie
          LLM::Interrupt.new
        else
          Return.new(id, name, value)
        end
      end
    end
    alias_method :value, :wait

    ##
    # @return [Class]
    def group_class
      LLM::Function::Ractor::Group
    end

    private

    ##
    # Builds the one ractor a task spawns: it runs the tool, and it is
    # the only thing that writes to the port.
    # @param [Ractor::Port] port
    # @return [Ractor]
    def build_task(port)
      @started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      vars = [port, @runner_class, @id, @name, @arguments, @cookie]
      Ractor.new(*vars) do |*vars|
        LLM::Function::Ractor::Job.new(*vars).call
      end
    end

    ##
    # Reads the monitor port, so that the ractor ending is something this
    # object knows rather than something it has to ask about.
    #
    # It is a thread of the caller's ractor rather than anything the
    # tool ractor runs, because a port can only be read from the ractor
    # that made it - and this is the ractor the task lives in.
    # @return [Thread]
    def watch_exit
      exits = @exits
      ::Thread.new do
        exits.receive
        @exited = true
      end
    end
  end
end
