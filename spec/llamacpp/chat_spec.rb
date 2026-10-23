# frozen_string_literal: true

require "setup"

RSpec.describe "LLM::Context: llamacpp" do
  let(:provider) { LLM.llamacpp(host:) }
  let(:host) { ENV["LLAMACPP_HOST"] || "localhost" }
  let(:ctx) { LLM::Context.new(provider, params.merge(model: "qwen3")) }
  let(:params) { {} }
  vcr = lambda { {vcr: {cassette_name: "llamacpp/chat/#{it}"}} }

  context LLM::Context do
    include_examples "LLM::Context: completions", :llamacpp

    context "when the model returns reasoning content", vcr.call("llm_reasoning_content") do
      it "exposes reasoning content on the assistant message" do
        ctx.talk("What is the date?")
        expect(ctx.messages.find(&:assistant?).reasoning_content).to be_a(String)
      end
    end
  end

  context LLM::Function do
    include_examples "LLM::Context: functions", :llamacpp, allow_playback_repeats: true
  end

  context LLM::Schema do
    include_examples "LLM::Context: schema", :llamacpp
  end
end
