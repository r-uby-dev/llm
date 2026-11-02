# frozen_string_literal: true

require "setup"
require "llm/providers/openai"

RSpec.describe "LLM::Agent in a ractor" do
  let(:agent) { stub_const("TestAgent", Ractor.make_shareable(Class.new(LLM::Agent))) }
  let(:name) do
    Ractor.new(agent) do |klass|
      llm = LLM.openai(key: "test")
      klass.new(llm).name
    end.value
  end

  it "derives a name for a class that never had one set" do
    expect(name).to eq("test-agent")
  end

  it "derives the same name on the main ractor" do
    expect(agent.name).to eq("test-agent")
  end
end
