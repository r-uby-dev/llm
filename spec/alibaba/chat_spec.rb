# frozen_string_literal: true

require "setup"

RSpec.describe "LLM::Context: alibaba" do
  let(:provider) { LLM.alibaba(key:) }
  let(:llm) { provider }
  let(:key) { ENV["DASHSCOPE_API_KEY"] || "TOKEN" }
  let(:ctx) { LLM::Context.new(provider, params) }
  let(:params) { {} }

  context LLM::Context do
    include_examples "LLM::Context: completions", :alibaba
    include_examples "LLM::Context: completions contract", :alibaba
    include_examples "LLM::Context: text stream", :alibaba
  end

  context LLM::Agent do
    include_examples "LLM::Agent: skill", :alibaba
  end

  context "when given a tool call", vcr: {cassette_name: "alibaba/chat/llm_chat_stream_tool"} do
    let(:params) { {stream: true, tools: [tool]} }
    let(:tool) do
      LLM.function(:system) do |fn|
        fn.description "Runs system commands"
        fn.params { it.object(command: it.string.required) }
        fn.define { |command:| {success: true, output: "Mon Jul 10 12:34:56 UTC 2026"} }
      end
    end
    let(:prompt) do
      ctx.build_prompt do
        it.user "You are a bot that can run UNIX system commands"
        it.user "Hey, run the 'date' command"
      end
    end

    before { ctx.talk(prompt) }

    it "calls the function(s)" do
      ctx.talk ctx.pending_functions.map(&:call)
      expect(ctx.pending_functions).to be_empty
    end
  end

  context LLM::Function do
    include_examples "LLM::Context: functions", :alibaba
  end

  context LLM::Schema do
    include_examples "LLM::Context: schema", :alibaba
  end
end
