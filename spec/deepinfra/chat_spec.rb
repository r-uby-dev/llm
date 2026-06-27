# frozen_string_literal: true

require "setup"

RSpec.describe "LLM::Context: deepinfra" do
  let(:provider) { LLM.deepinfra(key:) }
  let(:key) { ENV["DEEPINFRA_SECRET"] || "TOKEN" }
  let(:ctx) { LLM::Context.new(provider, params) }
  let(:params) { {} }

  context LLM::Context do
    include_examples "LLM::Context: completions", :deepinfra
    include_examples "LLM::Context: text stream", :deepinfra
    include_examples "LLM::Context: tool stream", :deepinfra
  end

  context LLM::Function do
    include_examples "LLM::Context: functions", :deepinfra
  end

  context LLM::Schema do
    include_examples "LLM::Context: schema", :deepinfra
  end
end
