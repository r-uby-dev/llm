# frozen_string_literal: true

require "setup"
require "stringio"

RSpec.describe LLM::Tracer::Logger do
  let(:provider) { LLM::OpenAI.new }
  let(:io) { StringIO.new }
  let(:tracer) { described_class.new(provider, io:) }
  let(:openai) do
    Class.new do
      def initialize
        @host = "api.openai.com"
        @port = 443
      end
    end
  end

  before { stub_const("LLM::OpenAI", openai) }

  describe "#on_request_start" do
    context "when given a chat operation" do
      subject(:output) { io.string }
      before { tracer.on_request_start(operation: "chat", model: "test-model") }

      it { is_expected.to include("request.start") }
      it { is_expected.to include("test-model") }
    end
  end

  describe "#on_request_finish" do
    context "when given a retrieval operation" do
      subject(:output) { io.string }
      let(:res) { double("LLM::Response", size: 1, has_more: false) }
      before { tracer.on_request_finish(operation: "retrieval", model: nil, res:) }

      it { is_expected.to include("request.finish") }
      it { is_expected.to include("openai_vector_store_search_result_count") }
      it { is_expected.to include("openai_vector_store_search_has_more") }
    end
  end

  describe "#on_tool_start" do
    subject(:output) { io.string }
    let(:span) { tracer.on_tool_start(id: "call_1", name: "tool", arguments: {q: 1}, model: "gpt-4.1") }
    before { span }

    it { is_expected.to include("tool.start") }

    ##
    # The return value is what the endings are handed, so a
    # tracer that gives back the logger's own value instead
    # gives them nothing to name the call by.
    it "returns a span the endings can name the call with" do
      expect(span.to_h).to eq({id: "call_1", name: "tool"})
    end
  end

  describe "#on_tool_finish" do
    subject(:output) { io.string }
    let(:result) { LLM::Function::Return.new("call_1", "tool", {ok: true}) }
    before { tracer.on_tool_finish(result:) }
    it { is_expected.to include("tool.finish") }
  end

  describe "#on_tool_error" do
    subject(:output) { io.string }
    let(:ex) { RuntimeError.new("yabadabadoo") }
    before { tracer.on_tool_error(ex:) }
    it { is_expected.to include("tool.error") }
  end
end
