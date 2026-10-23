# frozen_string_literal: true

class LLM::Function
  ##
  # Wraps a ractor-backed function call.
  #
  # One ractor runs the tool and hands its result to a
  # {Ractor::Port} the task reads. A thread inside the
  # ractor services interrupts, and the port is the only
  # way a result leaves.
  class Ractor::Task < LLM::Function::Task
    ##
    # @api private
    Ractor = ::Ractor
    private_constant :Ractor

    ##
    # Forwarded into the result port when the ractor ends,
    # so {#wait} reads one port rather than two.
    # @return [Symbol]
    EXITED = :__ractor_exited__
    private_constant :EXITED

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
    # @return [Boolean]
    def alive?
      return false if @result
      @ractor ? !@exited : false
    end

    ##
    # Tells the tool to stop.
    #
    # A cancel that arrives before `spawn` is remembered and
    # delivered by it.
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
    # Reads the result port, which holds the ractor's
    # result or the ending the exit watcher forwarded.
    # Later waits answer from memory.
    # @return [LLM::Function::Return]
    def wait
      return @intercepted if intercepted?
      @result ||= begin
        spawn unless @port
        _, ready = Ractor.select(@port)
        if ready == EXITED
          Return.new(id, name, {error: true, type: "ractor ended without result"})
        else
          _, id, name, value, @finished_at = ready
          if Hash === value and value[:interrupt] and value[:cookie] == @cookie
            LLM::Interrupt.new
          else
            Return.new(id, name, value)
          end
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
    # The monitor port's only reader: `Ractor#monitor`
    # sends `:exited` once, so a second reader is a
    # message one of them never hears. The ending goes
    # on to the result port, where {#wait} reads it.
    # @return [Thread]
    def watch_exit
      ::Thread.new do
        ractor_rescue { @exits.receive }
        @exited = true
        ractor_rescue { @port.send(EXITED) }
      end
    end

    ##
    # Runs a block that talks to a port, and answers nil
    # when the ractor it belongs to has gone - which is
    # what receiving from a closed port and sending to a
    # dead ractor both raise.
    # @yield
    # @return [Object, nil]
    def ractor_rescue(&block)
      block.call
    rescue ::Ractor::Error
      nil
    end
  end
end
