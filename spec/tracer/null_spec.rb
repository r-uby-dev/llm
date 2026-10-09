# frozen_string_literal: true

require "setup"

RSpec.describe LLM::Tracer::Null do
  let(:provider) { LLM.openai(key: "test") }
  let(:tracer) { described_class.new(provider) }

  describe "callbacks" do
    let(:ex) { RuntimeError.new("yabadabadoo") }
    let(:res) { double("LLM::Response") }

    it "noops on request callbacks" do
      expect(tracer.on_request_start(operation: "chat", model: "test-model")).to be_nil
      expect(tracer.on_request_finish(operation: "chat", model: "test-model", res:)).to be_nil
      expect(tracer.on_request_error(ex:, span: nil)).to be_nil
    end

    it "noops on tool callbacks" do
      expect(tracer.on_tool_start(id: "call_1", name: "tool", arguments: {})).to be_nil
      expect(tracer.on_tool_finish(result: LLM::Function::Return.new("call_1", "tool", {}))).to be_nil
      expect(tracer.on_tool_error(ex:, span: nil)).to be_nil
    end
  end
end
