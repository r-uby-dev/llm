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

  context "when given a tool call", vcr: {cassette_name: "alibaba/chat/llm_chat_stream_tool"} do
    let(:params) { {stream: true, tools: [tool]} }
    let(:tool) do
      LLM.function(:"get-date") do |fn|
        fn.description "Returns the current date"
        fn.define { {today: Date.today} }
      end
    end
    let(:prompt) do
      ctx.build_prompt do
        it.user "You are a bot that can tell the current date"
        it.user "Hey, what is the date today?"
      end
    end

    before { ctx.talk(prompt) }

    it "calls the function(s)" do
      returns = ctx.pending_functions.map(&:call)
      expect(returns.map(&:value)).to eq([{today: Date.today}])
      ctx.talk returns
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
