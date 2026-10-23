# frozen_string_literal: true

require "setup"
require "tempfile"

RSpec.describe LLM::RequestAdapter::Tool do
  let(:openai) { LLM.openai(key: "test") }
  let(:deepseek) { LLM.deepseek(key: "test") }
  let(:google) { LLM.google(key: "test") }
  let(:anthropic) { LLM.anthropic(key: "test") }

  let(:tool_calls) do
    [{id: "call_1", name: "system", arguments: {command: "date"}}]
  end

  let(:tool_return) do
    LLM::Function::Return.new("call_1", "system", {success: true})
  end

  let(:messages) do
    [
      LLM::Message.new("user", "what is the date?"),
      LLM::Message.new("assistant", nil, tool_calls:),
      LLM::Message.new("tool", [tool_return])
    ]
  end

  let(:saved) { LLM::Context.new(openai, mode: :responses) }

  let(:file) { Tempfile.open(["llmrb", ".json"]) }

  before do
    saved.messages.concat(messages)
    saved.serialize(path: file.path)
  end

  after { file.close }

  describe "a conversation saved under OpenAI Responses" do
    let(:restored) { LLM::Context.new(llm).deserialize(path: file.path) }
    let(:payload) { llm.send(:adapt, restored.messages) }
    let(:llm) { deepseek }

    it "restores into DeepSeek with completions-shaped tool calls" do
      expect(payload[1][:tool_calls]).to eq([{
        id: "call_1",
        type: "function",
        function: {name: "system", arguments: "{\"command\":\"date\"}"}
      }])
    end

    context "when restored into Google" do
      let(:llm) { google }

      it "uses functionCall parts" do
        expect(payload[1][:parts]).to eq([{
          functionCall: {name: "system", args: {"command" => "date"}}
        }])
      end
    end

    context "when restored into Anthropic" do
      let(:llm) { anthropic }

      it "uses tool_use blocks" do
        expect(payload[:messages][1][:content]).to eq([{
          type: "tool_use", id: "call_1", name: "system", input: {"command" => "date"}
        }])
      end
    end

    context "when the payload is read back" do
      let(:payload) { JSON.parse(File.read(file.path)) }

      it "holds the abstract tool calls" do
        expect(payload.dig("messages", 1, "tools"))
          .to eq([{"id" => "call_1", "name" => "system", "arguments" => {"command" => "date"}}])
      end
    end
  end

  describe "a Google tool call with a signature" do
    let(:tool_calls) do
      [{id: "call_1", name: "system", arguments: {command: "date"}, signature: "abc123"}]
    end

    let(:saved) { LLM::Context.new(google) }
    let(:restored) { LLM::Context.new(llm).deserialize(path: file.path) }
    let(:payload) { llm.send(:adapt, restored.messages) }
    let(:llm) { google }

    it "replays the signature after a restore" do
      expect(payload[1][:parts].first[:thoughtSignature]).to eq("abc123")
    end

    context "when restored into another provider" do
      let(:llm) { deepseek }

      it "drops the signature" do
        expect(payload[1][:tool_calls].first).not_to have_key(:signature)
      end
    end
  end

  describe "a version 1 Google tool call" do
    let(:document) do
      {
        schema_version: 1,
        messages: [
          {"role" => "user", "content" => "what is the date?"},
          {
            "role" => "assistant",
            "content" => nil,
            "tools" => [{id: "google_abc123", name: "system", arguments: {command: "date"}}]
          }
        ]
      }
    end

    let(:restored) do
      LLM::Context.new(google).deserialize(string: LLM.json.dump(document))
    end

    let(:payload) { google.send(:adapt, restored.messages) }

    it "recovers the signature its id carries" do
      expect(payload[1][:parts].first[:thoughtSignature]).to eq("abc123")
    end

    it "keeps the call itself" do
      expect(payload[1][:parts].first[:functionCall][:name]).to eq("system")
    end
  end
end
