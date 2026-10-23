# frozen_string_literal: true

require "setup"
require "llm/providers/mistral"

RSpec.describe "LLM::Mistral tool adaptation" do
  let(:provider) { LLM.mistral(key: "test") }

  let(:tool) do
    LLM.function(:system) do |fn|
      fn.description "Runs system commands"
      fn.params { it.object(command: it.string.required) }
      fn.define { |command:| {success: Kernel.system(command)} }
    end
  end

  describe "#normalize_complete_params" do
    subject(:normalized) { provider.send(:normalize_complete_params, tools: [tool]) }

    it "keeps the nested function payload" do
      params, = normalized
      expect(params[:tools]).to eq([{
        type: "function",
        function: {
          name: :system,
          description: "Runs system commands",
          parameters: tool.params.to_h
        }
      }])
    end

    it "removes the top-level tool name" do
      params, = normalized
      expect(params[:tools].first).not_to have_key(:name)
    end
  end

  describe "#adapt" do
    let(:assistant) do
      LLM::Message.new("assistant", nil, {
        tool_calls: [{id: "call_1", name: "system", arguments: {command: "date"}}]
      })
    end

    let(:result) do
      LLM::Function::Return.new("call_1", "system", {success: true})
    end

    it "includes tool name on tool result messages" do
      payload = provider.send(:adapt, [assistant, LLM::Message.new(:tool, result)], mode: :complete)
      expect(payload.last).to eq(
        role: "tool",
        name: "system",
        tool_call_id: "call_1",
        content: "{\"success\":true}"
      )
    end
  end
end
