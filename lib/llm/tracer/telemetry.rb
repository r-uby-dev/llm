# frozen_string_literal: true

require "digest"

module LLM
  ##
  # The {LLM::Tracer::Telemetry LLM::Tracer::Telemetry} tracer provides
  # telemetry support through the [opentelemetry-ruby](https://github.com/open-telemetry/opentelemetry-ruby)
  # RubyGem. The gem should be installed separately since this feature is opt-in
  # and disabled by default.
  #
  # @see https://github.com/open-telemetry/semantic-conventions/blob/main/docs/gen-ai Telemetry specs (index)
  # @see https://github.com/open-telemetry/semantic-conventions/blob/main/docs/gen-ai/openai.md Telemetry specs (OpenAI)
  #
  # @example InMemory export
  #   #!/usr/bin/env ruby
  #   require "llm"
  #   require "pp"
  #
  #   llm = LLM.openai(key: ENV["KEY"])
  #   llm.tracer = LLM::Tracer::Telemetry.new(llm)
  #
  #   ctx = LLM::Context.new(llm)
  #   ctx.talk "hello"
  #   ctx.talk "how are you?"
  #   ctx.tracer.spans.each { |span| pp span }
  #
  # @example OTLP export
  #   #!/usr/bin/env ruby
  #   require "llm"
  #   require "opentelemetry-exporter-otlp"
  #
  #   endpoint = "https://api.smith.langchain.com/otel/v1/traces"
  #   exporter = OpenTelemetry::Exporter::OTLP::Exporter.new(endpoint:)
  #
  #   llm = LLM.openai(key: ENV["KEY"])
  #   llm.tracer = LLM::Tracer::Telemetry.new(llm, exporter:)
  #
  #   ctx = LLM::Context.new(llm)
  #   ctx.talk "hello"
  #   ctx.talk "how are you?"
  class Tracer::Telemetry < Tracer
    ##
    # param [LLM::Provider] provider
    #  An LLM provider
    # @return [LLM::Tracer::Telemetry]
    def initialize(provider, options = {})
      super
      @exporter = options.delete(:exporter)
      setup!
    end

    ##
    # When +trace_group_id+ is provided, it is converted to an OpenTelemetry
    # trace_id (via a deterministic 16-byte hash) so all spans until {#stop_trace}
    # share that trace_id and appear as one trace in OTLP/Langfuse.
    #
    # @param (see LLM::Tracer#start_trace)
    # @return [self]
    def start_trace(trace_group_id: nil, name: "llm", attributes: {}, metadata: nil)
      return self if trace_group_id.to_s.empty?

      span_context = span_context_from_trace_group_id(trace_group_id.to_s)
      parent_ctx = ::OpenTelemetry::Trace.context_with_span(
        ::OpenTelemetry::Trace.non_recording_span(span_context)
      )
      attrs = attributes.compact
      attrs["llm.trace_group_id"] = trace_group_id.to_s
      root_span = @tracer.start_span(
        name,
        kind: :server,
        attributes: attrs,
        with_parent: parent_ctx
      )
      @root_span = root_span
      @root_context = ::OpenTelemetry::Trace.context_with_span(root_span)
      self
    end

    ##
    # @return [self]
    def stop_trace
      @root_span&.finish
      @root_span = nil
      @root_context = nil
      self
    end

    ##
    # @param (see LLM::Tracer#on_request_start)
    def on_request_start(operation:, model: nil, inputs: nil)
      case operation
      when "chat" then start_chat(operation:, model:, inputs:)
      when "retrieval" then start_retrieval(operation:)
      else nil
      end
    end

    ##
    # @param (see LLM::Tracer#on_request_finish)
    def on_request_finish(operation:, res:, model: nil, span: nil, outputs: nil, metadata: nil)
      return nil unless span
      case operation
      when "chat" then finish_chat(operation:, model:, res:, span:, outputs:, metadata:)
      when "retrieval" then finish_retrieval(operation:, res:, span:)
      else nil
      end
    end

    ##
    # @param (see LLM::Tracer#on_request_error)
    def on_request_error(ex:, span:)
      return nil unless span
      attributes = {"error.type" => ex.class.to_s}.compact
      attributes.each { span.set_attribute(_1, _2) }
      span.add_event("gen_ai.request.finish")
      span.status = ::OpenTelemetry::Trace::Status.error(ex.message)
      span.tap(&:finish)
    end

    ##
    # @param (see LLM::Tracer#on_tool_start)
    # @return (see LLM::Tracer#on_tool_start)
    def on_tool_start(id:, name:, arguments:, model:)
      attributes = {
        "gen_ai.operation.name" => "execute_tool",
        "gen_ai.request.model" => model,
        "gen_ai.tool.call.id" => id,
        "gen_ai.tool.name" => name&.to_s,
        "gen_ai.tool.call.arguments" => LLM.json.dump(arguments),
        "gen_ai.provider.name" => provider_name,
        "server.address" => provider_host,
        "server.port" => provider_port
      }.merge!(trace_attributes(span_kind: "tool")).compact
      span_name = ["execute_tool", name].compact.join(" ")
      span = create_span(span_name.empty? ? "gen_ai.tool" : span_name, attributes:)
      span.add_event("gen_ai.tool.start")
      span
    end

    ##
    # @param (see LLM::Tracer#on_tool_finish)
    # @return (see LLM::Tracer#on_tool_finish)
    def on_tool_finish(result:, span:)
      return nil unless span
      attributes = {
        "gen_ai.tool.call.id" => result.id,
        "gen_ai.tool.name" => result.name&.to_s,
        "gen_ai.tool.call.result" => LLM.json.dump(result.value)
      }.compact
      attributes.each { span.set_attribute(_1, _2) }
      span.add_event("gen_ai.tool.finish")
      span.tap(&:finish)
    end

    ##
    # @param (see LLM::Tracer#on_tool_error)
    # @return (see LLM::Tracer#on_tool_error)
    def on_tool_error(ex:, span:)
      return nil unless span
      attributes = {"error.type" => ex.class.to_s}.compact
      attributes.each { span.set_attribute(_1, _2) }
      span.add_event("gen_ai.tool.finish")
      span.status = ::OpenTelemetry::Trace::Status.error(ex.message)
      span.tap(&:finish)
    end

    ##
    # @note
    # This method returns an empty array for exporters that
    # do not implement 'finished_spans' such as the OTLP
    # exporter
    # @return [Array<OpenTelemetry::SDK::Trace::SpanData>]
    def spans
      return [] unless @exporter.respond_to?(:finished_spans)
      flush!
      @exporter.finished_spans
    end

    ##
    # Flushes queued telemetry to the configured exporter.
    # @note
    #  Exports are batched in the background by default.
    #  Long-lived processes usually do not need to call this method.
    #  Short-lived scripts should call {#flush!} before exit to reduce
    #  the risk of losing spans that are still buffered.
    # @return (see LLM::Tracer#flush!)
    def flush!
      @tracer_provider.force_flush
      nil
    end

    private

    ##
    # @api private
    def create_span(name, kind: :client, attributes: {})
      root_context = @root_context
      opts = {kind:, attributes:}
      opts[:with_parent] = root_context if root_context
      @tracer.start_span(name, **opts)
    end

    ##
    # Converts a string trace_group_id to an OpenTelemetry SpanContext so all
    # spans created with this context share the same trace_id.
    # @api private
    def span_context_from_trace_group_id(trace_group_id)
      trace_id = Digest::MD5.digest(trace_group_id)
      trace_id = ::OpenTelemetry::Trace.generate_trace_id if trace_id == ::OpenTelemetry::Trace::INVALID_TRACE_ID
      span_id = Digest::SHA256.digest(trace_group_id)[0, 8]
      span_id = ::OpenTelemetry::Trace.generate_span_id if span_id == ::OpenTelemetry::Trace::INVALID_SPAN_ID
      ::OpenTelemetry::Trace::SpanContext.new(
        trace_id:,
        span_id:,
        trace_flags: ::OpenTelemetry::Trace::TraceFlags::SAMPLED
      )
    end

    ##
    # @api private
    def setup!
      require "opentelemetry/sdk" unless defined?(OpenTelemetry)
      @exporter ||= OpenTelemetry::SDK::Trace::Export::InMemorySpanExporter.new
      processor = OpenTelemetry::SDK::Trace::Export::BatchSpanProcessor.new(@exporter)
      @tracer_provider = OpenTelemetry::SDK::Trace::TracerProvider.new(
        sampler: OpenTelemetry::SDK::Trace::Samplers::ALWAYS_ON
      )
      @tracer_provider.add_span_processor(processor)
      @tracer = @tracer_provider.tracer("llm.rb", LLM::VERSION)
    end

    ##
    # @param [String] operation
    # @param [LLM::Response] res
    # @api private
    def finish_attributes(operation, res)
      case @llm.class.to_s
      when "LLM::OpenAI" then openai_attributes(operation, res)
      else {}
      end
    end

    ##
    # @param [String] operation
    # @param [LLM::Response] res
    # @api private
    def openai_attributes(operation, res)
      case operation
      when "chat"
        {
          "openai.response.service_tier" => res.service_tier,
          "openai.response.system_fingerprint" => res.system_fingerprint
        }
      when "retrieval"
        {
          "openai.vector_store.search.result_count" => res.size,
          "openai.vector_store.search.has_more" => res.has_more
        }
      else {}
      end
    end

    ##
    # start_*

    def start_chat(operation:, model:, inputs: nil)
      request_metadata = consume_request_metadata
      input_value = request_metadata[:user_input]
      attributes = {
        "gen_ai.operation.name" => operation,
        "gen_ai.request.model" => model,
        "gen_ai.provider.name" => provider_name,
        "server.address" => provider_host,
        "server.port" => provider_port,
        "input.value" => serialize_request_value(input_value)
      }.merge!(trace_attributes(span_kind: "llm")).compact
      span_name = [operation, model].compact.join(" ")
      span = create_span(span_name.empty? ? "gen_ai.request" : span_name, attributes:)
      set_span_attributes(span, consume_extra_inputs.merge(inputs || {}))
      span.add_event("gen_ai.request.start")
      span
    end

    def start_retrieval(operation:)
      attributes = {
        "gen_ai.operation.name" => operation,
        "gen_ai.provider.name" => provider_name,
        "server.address" => provider_host,
        "server.port" => provider_port
      }.merge!(trace_attributes(span_kind: "retriever")).compact
      span = create_span(operation, attributes:)
      span.add_event("gen_ai.request.start")
      span
    end

    ##
    # finish_*

    def finish_chat(operation:, model:, res:, span:, outputs: nil, metadata: nil)
      output_value = if res.respond_to?(:output_text)
        res.output_text
      else
        (res.respond_to?(:content) ? res.content : nil)
      end
      attributes = {
        "gen_ai.operation.name" => operation,
        "gen_ai.request.model" => model,
        "gen_ai.response.id" => res.id,
        "gen_ai.response.model" => model,
        "gen_ai.usage.input_tokens" => res.usage.input_tokens,
        "gen_ai.usage.output_tokens" => res.usage.output_tokens,
        "output.value" => serialize_request_value(output_value)
      }.merge!(finish_attributes(operation, res)).compact
      attributes.each { span.set_attribute(_1, _2) }
      set_span_attributes(span, consume_extra_outputs.merge(outputs || {}))
      finish_metadata = consume_finish_metadata_proc(res)
      metadata = (metadata || {}).merge(finish_metadata || {})
      set_span_attributes(span, metadata.transform_keys { "langsmith.metadata.#{_1}" })
      span.add_event("gen_ai.request.finish")
      span.tap(&:finish)
    end

    def finish_retrieval(operation:, res:, span:)
      attributes = {
        "gen_ai.operation.name" => operation
      }.merge!(finish_attributes(operation, res)).compact
      chunks_json = retrieval_chunks_json(res)
      attributes["langsmith.metadata.chunks"] = chunks_json if chunks_json
      attributes.each { span.set_attribute(_1, _2) }
      span.add_event("gen_ai.request.finish")
      span.tap(&:finish)
    end

    ##
    # @api private
    # Serialize retrieval response chunks for span attributes (e.g. langsmith.metadata.chunks).
    # Returns a JSON string or nil when res has no data.
    def consume_finish_metadata_proc(res)
      key = LLM::Tracer::FINISH_METADATA_PROC_KEY
      proc = Thread.current[key]
      Thread.current[key] = nil
      return {} unless proc.respond_to?(:call)

      proc.call(res) || {}
    rescue
      {}
    end

    def retrieval_chunks_json(res)
      return nil unless res.respond_to?(:data)

      data = res.data
      return nil unless data.is_a?(Array)

      payload = data.map { |c| c.respond_to?(:to_h) ? c.to_h : c }
      LLM.json.dump(payload)
    rescue
      nil
    end

    ##
    # @api private
    # Hook for tracer-specific span attributes.
    # Subclasses can override this to inject provider-agnostic tags.
    def trace_attributes(span_kind:)
      {}
    end

    ##
    # @api private
    # Sets attribute key-value pairs on the span, serializing non-primitive values to JSON.
    def set_span_attributes(span, attrs)
      return if attrs.nil? || attrs.empty?

      attrs.each do |key, value|
        span.set_attribute(key.to_s, serialize_span_value(value))
      end
    end

    ##
    # @api private
    # OpenTelemetry attributes accept String, Numeric, Boolean, or Array of those.
    # Complex values (hashes, arrays of objects) are serialized to JSON strings.
    def serialize_span_value(value)
      case value
      when String, Numeric, TrueClass, FalseClass
        value
      when Array
        value.all? { |v| v.is_a?(String) || v.is_a?(Numeric) || v == true || v == false } ? value : LLM.json.dump(value)
      else
        LLM.json.dump(value)
      end
    end

    def serialize_request_value(value)
      case value
      when nil
        nil
      when String
        value
      else
        LLM.json.dump(value)
      end
    end
  end
end
