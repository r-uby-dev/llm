# frozen_string_literal: true

require "setup"

RSpec.describe "LLM::Context: zai" do
  let(:provider) { LLM.zai(key:) }
  let(:key) { ENV["ZAI_SECRET"] || "TOKEN" }
  let(:ctx) { LLM::Context.new(provider, params) }
  let(:params) { {} }

  context LLM::Context do
    include_examples "LLM::Context: completions", :zai
    include_examples "LLM::Context: text stream", :zai
    include_examples "LLM::Context: tool stream", :zai
  end

  context LLM::Function do
  end
end
