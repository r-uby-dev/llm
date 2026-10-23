# frozen_string_literal: true

require "setup"
require "tempfile"
require "llm/providers/anthropic"

RSpec.describe LLM::RequestAdapter::Role do
  let(:google) { LLM.google(key: "test") }
  let(:openai) { LLM.openai(key: "test") }
  let(:anthropic) { LLM.anthropic(key: "test") }

  let(:tool_return) do
    LLM::Function::Return.new("call_1", "system", {success: true})
  end

  describe "when given Gemini messages" do
    let(:messages) do
      [
        LLM::Message.new("user", "what is the date?"),
        LLM::Message.new("model", ""),
        LLM::Message.new("user", [tool_return]),
        LLM::Message.new("model", "2025-08-24")
      ]
    end

    it "is saved with abstract roles" do
      expect(messages.map(&:role)).to eq(["user", "assistant", "tool", "assistant"])
    end

    it "is assembled for OpenAI with assistant and tool" do
      expect(roles(openai)).to eq(["user", "assistant", "tool", "assistant"])
    end

    it "is assembled for Anthropic with a user tool return" do
      expect(roles(anthropic)).to eq(["user", "assistant", "user", "assistant"])
    end

    it "is assembled for Google with model and user" do
      expect(roles(google)).to eq(["user", "model", "user", "model"])
    end

    context "with a saved conversation" do
      let(:file) { Tempfile.open(["llmrb", ".json"]) }
      let(:google_context) { LLM::Context.new(google) }
      let(:openai_context) { LLM::Context.new(openai) }

      before do
        google_context.messages.concat(messages)
        google_context.serialize(path: file.path)
      end

      after { file.close }

      it "restores the abstract roles it was saved with" do
        restored = openai_context.deserialize(path: file.path)
        expect(restored.messages.map(&:role)).to eq(["user", "assistant", "tool", "assistant"])
      end
    end
  end

  describe "when given OpenAI messages" do
    let(:messages) do
      [
        LLM::Message.new("user", "what is the date?"),
        LLM::Message.new("assistant", ""),
        LLM::Message.new("tool", [tool_return]),
        LLM::Message.new("assistant", "2025-08-24")
      ]
    end

    it "is assembled for Google with model and user" do
      expect(roles(google)).to eq(["user", "model", "user", "model"])
    end

    it "is assembled for Anthropic with a user tool return" do
      expect(roles(anthropic)).to eq(["user", "assistant", "user", "assistant"])
    end
  end

  private

  def roles(llm)
    payload = llm.send(:adapt, messages.dup)
    payload = payload[:messages] if Hash === payload
    payload.flat_map { Array === it ? it.map { it[:role] } : it[:role] }
  end
end
