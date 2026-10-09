# frozen_string_literal: true

require "setup"

RSpec.describe LLM::Tracer do
  let(:provider) { LLM.openai(key: "test") }
  let(:tracer) { described_class.new(provider) }
  let(:request_id) { SecureRandom.uuid_v7 }

  describe "#spans" do
    it "returns an empty array" do
      expect(tracer.spans).to eq([])
    end
  end

  describe "#flush!" do
    it "returns nil" do
      expect(tracer.flush!).to be_nil
    end
  end

  describe "#on_exit" do
    it "returns nil" do
      expect(tracer.on_exit).to be_nil
    end
  end

  describe "#on_request_start" do
    it "raises NotImplementedError" do
      expect {
        tracer.on_request_start(operation: "chat", model: "test-model", request_id:)
      }.to raise_error(NotImplementedError)
    end
  end

  describe "#on_request_finish" do
    let(:res) { double("LLM::Response") }

    it "raises NotImplementedError" do
      expect {
        tracer.on_request_finish(operation: "chat", model: "test-model", res:, request_id:)
      }.to raise_error(NotImplementedError)
    end
  end

  describe "#on_request_error" do
    let(:ex) { RuntimeError.new("yabadabadoo") }

    it "raises NotImplementedError" do
      expect {
        tracer.on_request_error(ex:, span: nil, request_id:)
      }.to raise_error(NotImplementedError)
    end
  end

  describe "#on_tool_start" do
    it "raises NotImplementedError" do
      expect {
        tracer.on_tool_start(id: "call_1", name: "tool", arguments: {q: 1}, model: "gpt-4.1")
      }.to raise_error(NotImplementedError)
    end
  end

  describe "#on_tool_finish" do
    let(:result) { LLM::Function::Return.new("call_1", "tool", {ok: true}) }

    it "raises NotImplementedError" do
      expect {
        tracer.on_tool_finish(result:, span: nil)
      }.to raise_error(NotImplementedError)
    end
  end

  describe "#on_tool_error" do
    let(:ex) { RuntimeError.new("yabadabadoo") }

    it "raises NotImplementedError" do
      expect {
        tracer.on_tool_error(ex:, span: nil)
      }.to raise_error(NotImplementedError)
    end
  end
end
