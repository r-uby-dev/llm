# frozen_string_literal: true

require "setup"

RSpec.describe LLM::Tracer::Telemetry do
  let(:provider) { LLM.openai(key: "test") }
  let(:tracer) { described_class.new(provider) }
  let(:request_id) { SecureRandom.uuid_v7 }

  describe "#on_request_start" do
    context "when given a chat operation" do
      subject { tracer.on_request_start(operation: "chat", model: "test-model", request_id:) }
      it { is_expected.to be_a(OpenTelemetry::SDK::Trace::Span) }
    end

    context "when given a retrieval operation" do
      subject { tracer.on_request_start(operation: "retrieval", request_id:) }
      it { is_expected.to be_a(OpenTelemetry::SDK::Trace::Span) }
    end
  end

  describe "#on_request_finish" do
    context "when given a chat operation" do
      let(:usage) { LLM::Usage.new(input_tokens: 1, output_tokens: 2) }
      let(:res) { double("LLM::Response", id: "res_123", model: "test-model", usage:, service_tier: "default", system_fingerprint: "yabadabadoo") }
      let(:span) { tracer.on_request_start(operation: "chat", model: "test-model", request_id:) }
      let(:attributes) { {"gen_ai.operation.name" => "chat", "gen_ai.request.model" => "test-model"} }

      before { tracer.on_request_finish(operation: "chat", model: "test-model", res:, span:, request_id:) }

      it "finishes the span" do
        expect(span.name).to eq("chat test-model")
        expect(span.attributes).to match(hash_including(attributes))
      end
    end

    context "when the response reports a different model" do
      let(:usage) { LLM::Usage.new(input_tokens: 1, output_tokens: 2) }
      let(:res) do
        double("LLM::Response", id: "res_123", model: "resolved-model", usage:,
                                 service_tier: "default", system_fingerprint: "yabadabadoo")
      end
      let(:span) { tracer.on_request_start(operation: "chat", model: "openrouter/auto", request_id:) }

      before do
        tracer.on_request_finish(operation: "chat", model: "openrouter/auto", res:, span:, request_id:)
      end

      it "records the model the response reports" do
        expect(span.attributes["gen_ai.response.model"]).to eq("resolved-model")
      end

      it "keeps the requested model as the request model" do
        expect(span.attributes["gen_ai.request.model"]).to eq("openrouter/auto")
      end
    end

    context "when given a retrieval operation" do
      let(:res) { double("LLM::Response", size: 1, has_more: false) }
      let(:span) { tracer.on_request_start(operation: "retrieval", request_id:) }
      let(:attributes) { {"gen_ai.operation.name" => "retrieval"} }

      before { tracer.on_request_finish(operation: "retrieval", res:, span:, request_id:) }

      it "finishes the span" do
        expect(span.name).to eq("retrieval")
        expect(span.attributes).to match(hash_including(attributes))
      end
    end
  end

  describe "#on_request_error" do
    let(:ex) { RuntimeError.new("yabadabadoo") }
    let(:span) { tracer.on_request_start(operation: "chat", model: "test-model", request_id:) }

    before { tracer.on_request_error(ex:, span:, request_id:) }

    it "records error.type" do
      expect(tracer.spans.last.attributes["error.type"]).to eq("RuntimeError")
    end
  end

  describe "#on_tool_start" do
    subject { tracer.on_tool_start(id: "call_1", name: "tool", arguments: {q: 1}, model: "gpt-4.1") }
    it { is_expected.to be_a(OpenTelemetry::SDK::Trace::Span) }
  end

  describe "#on_tool_finish" do
    let(:span) { tracer.on_tool_start(id: "call_1", name: "tool", arguments: {q: 1}, model: "gpt-4.1") }
    let(:result) { LLM::Function::Return.new("call_1", "tool", {ok: true}) }

    before { tracer.on_tool_finish(result:, span:) }

    it "finishes the span" do
      expect(span.name).to eq("execute_tool tool")
      expect(span.attributes["gen_ai.tool.call.id"]).to eq("call_1")
    end
  end

  describe "#on_tool_error" do
    let(:ex) { RuntimeError.new("yabadabadoo") }
    let(:span) { tracer.on_tool_start(id: "call_1", name: "tool", arguments: {q: 1}, model: "gpt-4.1") }

    before { tracer.on_tool_error(ex:, span:) }

    it "records error.type" do
      expect(tracer.spans.last.attributes["error.type"]).to eq("RuntimeError")
    end
  end

  describe "#on_tool_interrupt" do
    let(:ex) { LLM::Interrupt.new }
    let(:span) { tracer.on_tool_start(id: "call_1", name: "tool", arguments: {q: 1}, model: "gpt-4.1") }

    before { tracer.on_tool_interrupt(ex:, span:) }

    it "finishes the span" do
      expect(tracer.spans.last.name).to eq("execute_tool tool")
    end

    it "does not record an error" do
      expect(tracer.spans.last.attributes).not_to have_key("error.type")
      expect(tracer.spans.last.status.ok?).to be(true)
    end

    it "adds an interrupt event of its own" do
      expect(tracer.spans.last.events.map(&:name)).to include("gen_ai.tool.interrupt")
    end
  end

  describe "#start_trace" do
    let(:span) { tracer.on_request_start(operation: "chat", model: "test-model", request_id:) }
    let(:res) { double("LLM::Response", id: "res_123", model: "test-model", usage: LLM::Usage.new(input_tokens: 1, output_tokens: 2), service_tier: "default", system_fingerprint: "yabadabadoo") }

    before do
      tracer.start_trace(trace_group_id: "turn-123", name: "chatbot.turn")
      tracer.on_request_finish(operation: "chat", model: "test-model", res:, span:, request_id:)
      tracer.stop_trace
    end

    it "records the root span name" do
      expect(tracer.spans.map(&:name)).to include("chatbot.turn")
    end

    it "groups child spans under the same trace" do
      expect(tracer.spans.map(&:trace_id).uniq.size).to eq(1)
    end
  end

  describe "#stop_trace" do
    before do
      tracer.start_trace(trace_group_id: "turn-123", name: "chatbot.turn")
      tracer.stop_trace
    end

    it "returns self" do
      expect(tracer.stop_trace).to equal(tracer)
    end
  end

  describe "#spans" do
    let(:tracer) { described_class.new(provider, exporter:) }
    let(:exporter) do
      Class.new do
        def export(*) = OpenTelemetry::SDK::Trace::Export::SUCCESS
        def shutdown(*) = OpenTelemetry::SDK::Trace::Export::SUCCESS
        def force_flush(*) = OpenTelemetry::SDK::Trace::Export::SUCCESS
      end.new
    end

    it "returns an empty array" do
      expect(tracer.spans).to eq([])
    end
  end

  describe "#flush!" do
    it "returns nil" do
      expect(tracer.flush!).to be_nil
    end
  end
end
