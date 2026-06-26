# frozen_string_literal: true

require "setup"

RSpec.describe "LLM::Context: google" do
  let(:provider) { LLM.google(key:) }
  let(:llm) { provider }
  let(:key) { ENV["GOOGLE_SECRET"] || "TOKEN" }
  let(:ctx) { LLM::Context.new(provider, params) }
  let(:params) { {} }

  context LLM do
    include_examples "LLM: web search", :google, match_requests_on: [:method]
  end

  context LLM::Context do
    include_examples "LLM::Context: completions", :google, match_requests_on: [:method]
    include_examples "LLM::Context: completions contract", :google, match_requests_on: [:method]
    include_examples "LLM::Context: text stream", :google, match_requests_on: [:method]
    include_examples "LLM::Context: tool stream", :google, match_requests_on: [:method]

    context "when given a Google function call id",
            vcr: {cassette_name: "google/chat/llm_function_class", match_requests_on: [:method]} do
      let(:tool) do
        Class.new(LLM::Tool) do
          name "system"
          description "Runs system commands"
          params { _1.object(command: _1.string.required) }
          def call(command:)
            {success: Kernel.system(command)}
          end
        end
      end
      let(:params) { {tools: [tool]} }

      before { ctx.talk("What is the date?") }

      it "synthesizes an id for the pending function" do
        expect(ctx.functions.first.id).to start_with("google_")
      end
    end

    describe ".tool_id" do
      it "uses thoughtSignature when given" do
        part = {"functionCall" => {"name" => "system"}, "thoughtSignature" => "abc123"}
        expect(LLM::Google.tool_id(part:, cindex: 0, pindex: 0)).to eq("google_abc123")
      end

      it "falls back to candidate and part indexes" do
        part = {"functionCall" => {"name" => "system"}}
        expect(LLM::Google.tool_id(part:, cindex: 2, pindex: 1)).to eq("google_call_2_1")
      end
    end

    context "when given tool stream response metadata",
            vcr: {cassette_name: "google/chat/llm_chat_stream_tool_metadata", match_requests_on: [:method]} do
      let(:params) { {stream: true, tools: [tool]} }
      let(:tool) do
        LLM.function(:system) do |fn|
          fn.description "Runs system commands"
          fn.params { _1.object(command: _1.string.required) }
          fn.define { |command:| {success: Kernel.system(command)} }
        end
      end
      let(:prompt) do
        ctx.build_prompt do
          _1.user "You are a bot that can run UNIX system commands"
          _1.user "Hey, run the 'date' command"
        end
      end

      before { ctx.talk(prompt) }

      it "preserves thoughtSignature on functionCall parts" do
        message = ctx.messages.find(&:assistant?)
        part = message.response.body.candidates[0].content.parts[0]
        expect(part.thoughtSignature).to be_a(String)
      end
    end
  end

  context LLM::Function do
    include_examples "LLM::Context: functions", :google, match_requests_on: [:method]
  end

  context LLM::File do
    include_examples "LLM::Context: files", :google, match_requests_on: [:method]
  end

  context LLM::Schema do
    include_examples "LLM::Context: schema", :google, match_requests_on: [:method]
  end
end
