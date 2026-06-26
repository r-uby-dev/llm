# frozen_string_literal: true

module LLM
  ##
  # The {LLM::Tracer LLM::Tracer} is the superclass of all
  # LLM tracers. It can be helpful for implementing instrumentation
  # and hooking into the lifecycle of an LLM request. See
  # {LLM::Tracer::Telemetry LLM::Tracer::Telemetry}, and
  # {LLM::Tracer::Logger LLM::Tracer::Logger} for example
  # tracer implementations.
  class Tracer
    require_relative "tracer/logger"
    require_relative "tracer/telemetry"
    require_relative "tracer/null"

    ##
    # @return [LLM::Provider]
    attr_reader :llm

    ##
    # @param [LLM::Provider] provider
    #  A provider
    # @param [Hash] options
    #  A hash of options
    def initialize(provider, options = {})
      @llm = provider
      @options = {}
    end

    ##
    # Called before an LLM provider request is executed.
    # @param [String] operation
    # @param [String] model
    # @param [Hash, nil] inputs Optional span attributes (e.g. gen_ai.input.messages) from llm.rb or caller.
    # @return [void]
    def on_request_start(operation:, model: nil, inputs: nil)
      raise NotImplementedError, "#{self.class} does not implement '#{__method__}'"
    end

    ##
    # Called after an LLM provider request succeeds.
    # @param [String] operation
    # @param [LLM::Response] res
    # @param [Object, nil] span
    # @param [String] model
    # @param [Hash, nil] outputs Optional span attributes (e.g. gen_ai.output.messages) from llm.rb or caller.
    # @param [Hash, nil] metadata Optional metadata from llm.rb or caller.
    # @return [void]
    def on_request_finish(operation:, res:, model: nil, span: nil, outputs: nil, metadata: nil)
      raise NotImplementedError, "#{self.class} does not implement '#{__method__}'"
    end

    ##
    # Called when an LLM provider request fails.
    # @param [LLM::Error] ex
    # @param [Object, nil] span
    # @return [void]
    def on_request_error(ex:, span:)
      raise NotImplementedError, "#{self.class} does not implement '#{__method__}'"
    end

    ##
    # Called before a local tool/function executes.
    # @param [String] id
    #  The tool call ID assigned by the model/provider
    # @param [String] name
    #  The tool (function) name.
    # @param [Hash] arguments
    #  The parsed tool arguments.
    # @param [String] model
    #  The model name
    # @return [void]
    def on_tool_start(id:, name:, arguments:, model:)
      raise NotImplementedError, "#{self.class} does not implement '#{__method__}'"
    end

    ##
    # Called after a local tool/function succeeds.
    # @param [LLM::Function::Return] result
    #  The tool return object.
    # @param [Object, nil] span
    #  The span/context object returned by {#on_tool_start}.
    # @return [void]
    def on_tool_finish(result:, span:)
      raise NotImplementedError, "#{self.class} does not implement '#{__method__}'"
    end

    ##
    # Called when a local tool/function raises.
    # @param [Exception] ex
    #  The raised error.
    # @param [Object, nil] span
    #  The span/context object returned by {#on_tool_start}.
    # @return [void]
    def on_tool_error(ex:, span:)
      raise NotImplementedError, "#{self.class} does not implement '#{__method__}'"
    end

    ##
    # Opens a trace group so subsequent LLM spans share the same OpenTelemetry
    # trace_id (and appear as one trace in backends like Langfuse).
    # When +trace_group_id+ is a string, it is used to derive the trace_id.
    #
    # @param [String, nil] trace_group_id
    #  Optional. When present, converted to a 16-byte trace_id so all spans
    #  created until {#stop_trace} are grouped in one trace.
    # @param [String] name
    #  Name for the root span (e.g. "chatbot.turn").
    # @param [Hash] attributes
    #  OpenTelemetry attributes to set on the root span.
    # @param [Hash, nil] metadata
    #  Optional. Trace-level metadata merged into the trace by tracers that support it.
    # @return [self]
    def start_trace(trace_group_id: nil, name: "llm", attributes: {}, metadata: nil)
      self
    end

    ##
    # Finishes the trace group started by {#start_trace}. Safe to call even if
    # no trace is active.
    # @return [self]
    def stop_trace
      self
    end

    ##
    # @return [String]
    def inspect
      "#<#{LLM::Utils.object_id(self)} @provider=#{@llm.class} @tracer=#{@tracer.inspect}>"
    end

    ##
    # @return [Array]
    def spans
      []
    end

    ##
    # Flush the tracer
    # @note
    #  This method is only implemented by the {LLM::Tracer::Telemetry} tracer.
    #  It is a noop for other tracers.
    # @return [nil]
    def flush!
      nil
    end

    ##
    # Merges extra attributes for the current trace/span. Used by applications
    # (e.g. chatbot) to add metadata, span inputs, or span outputs to the next
    # span or to the trace. No-op by default.
    #
    # @param [Hash, nil] metadata
    #  Key-value pairs merged into trace/span metadata.
    # @param [Hash, nil] inputs
    #  Key-value pairs set on the next span at start (e.g. gen_ai.input.messages).
    #  Consumed when the span is created.
    # @param [Hash, nil] outputs
    #  Key-value pairs set on the current span at finish (e.g. gen_ai.output.messages).
    #  Must be set before the request finishes (e.g. in a block passed to the provider).
    # @return [self]
    def merge_extra(metadata: nil, inputs: nil, outputs: nil)
      self
    end

    ##
    # Optional: set a proc to supply metadata when the next chat span finishes.
    # The proc is called with the response (res) and should return a Hash of
    # metadata (e.g. { intent: "...", confidence: 1.0 }) to merge onto the span.
    # Cleared after use. Used by apps to attach routing/intent that is only
    # known after the response.
    #
    # @param [Proc, nil] proc (res) -> Hash or nil
    # @return [self]
    def set_finish_metadata_proc(proc)
      thread[FINISH_METADATA_PROC_KEY] = proc
      self
    end

    FINISH_METADATA_PROC_KEY = :"llm.tracer.finish_metadata_proc"

    ##
    # Returns and clears extra inputs for the next span. Called by the telemetry
    # tracer when starting a span. Subclasses can override to return stored
    # inputs; default returns {}.
    #
    # @return [Hash] Attribute key => value to set on the span at start
    def consume_extra_inputs
      {}
    end

    ##
    # Returns and clears extra outputs for the current span. Called by the
    # telemetry tracer when finishing a span. Subclasses override to return
    # fiber-local outputs; default returns {}.
    #
    # @return [Hash] Attribute key => value to set on the span at finish
    def consume_extra_outputs
      {}
    end

    ##
    # Store per-request metadata (e.g. user_input) to be consumed by tracers
    # when starting the next span. Used for plain-text input.value / output.value.
    #
    # @param [Hash] metadata e.g. { user_input: "the user question" }
    # @return [nil]
    def set_request_metadata(metadata)
      return nil unless metadata && !metadata.empty?
      key = thread_request_metadata_key
      current = thread[key] || {}
      thread[key] = current.merge(metadata.compact)
      nil
    end

    ##
    # Consume and clear per-request metadata. Called by the telemetry tracer at span start.
    #
    # @return [Hash]
    def consume_request_metadata
      key = thread_request_metadata_key
      data = thread[key] || {}
      thread[key] = nil
      data
    end

    private

    def thread_request_metadata_key
      @thread_request_metadata_key ||= :"llm.tracer.request_metadata.#{object_id}"
    end

    def thread
      Thread.current
    end

    ##
    # @return [String]
    def provider_name
      @llm.class.name.split("::").last.downcase
    end

    ##
    # @return [String]
    def provider_host
      @llm.instance_variable_get(:@host)
    end

    ##
    # @return [String]
    def provider_port
      @llm.instance_variable_get(:@port)
    end
  end
end
