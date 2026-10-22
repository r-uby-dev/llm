# frozen_string_literal: true

require "setup"

RSpec.describe "LLM::Context: hanzo" do
  let(:provider) { LLM.hanzo(key:) }
  let(:key) { ENV["HANZO_API_KEY"] || "TOKEN" }
  let(:ctx) { LLM::Context.new(provider, params) }
  let(:params) { {} }

  context LLM::Context do
    include_examples "LLM::Context: completions", :hanzo
    include_examples "LLM::Context: text stream", :hanzo
    include_examples "LLM::Context: tool stream", :hanzo
    include_examples "LLM::Context: vision",      :hanzo
  end

  context LLM::Function do
    include_examples "LLM::Context: functions", :hanzo
  end

  context LLM::Schema do
    include_examples "LLM::Context: schema", :hanzo
  end
end
