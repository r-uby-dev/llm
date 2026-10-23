# frozen_string_literal: true

class LLM::Function
  ##
  # Wraps a ractor-backed function call.
  #
  # One ractor runs the tool and hands its result to a
  # {Ractor::Port} the task reads. A thread inside the
  # ractor services interrupts; the port is the only way
  # a result leaves.
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
    # A waited-on task answers false from its result, rather
    # than asking a ractor that has gone.
    #
    # Before that it is alive for as long as its ractor is,
    # which is what the monitor port says: it sends
    # `:exited` when the ractor ends, and the ractor ends
    # only after the result has been handed over.
    # @return [Boolean]
    def alive?
      return false if @result
      @ractor ? !@exited : false
    end

    ##
    # Tells the tool to stop.
    #
    # A cancel that arrives before `spawn` is remembered,
    # not lost: the ractor does not exist yet, so there is
    # nothing to send it to. `spawn` delivers it, which is
    # the first moment there is somewhere to deliver it.
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
    # The first wait reads the port the ractor delivered to,
    # which holds the result whether or not that ractor is
    # still there. Later waits answer from memory.
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
    # Builds the one ractor a task spawns: it runs the tool,
    # and it is the only thing that writes to the port.
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
    # Reads the monitor port, so the ractor ending is
    # something this object knows rather than asks about.
    #
    # The reader is a thread of the ractor the task lives
    # in, since a port can only be read by the ractor that
    # made it.
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
