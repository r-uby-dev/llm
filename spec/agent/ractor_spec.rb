# frozen_string_literal: true

require "setup"
require "llm/providers/openai"
require "llm/tools"

RSpec.describe "LLM::Agent in a ractor" do
  let(:agent) { stub_const("TestAgent", Ractor.make_shareable(Class.new(LLM::Agent))) }

  context "when given the name" do
    let(:name) do
      Ractor.new(agent) { TestAgent.name }.value
    end

    it "derives a name for a class that never had one set" do
      expect(name).to eq("test-agent")
    end

    it "derives the same name on the main ractor" do
      expect(agent.name).to eq("test-agent")
    end
  end

  context "when given tools" do
    let(:tools) do
      [LLM::Tool::ReadFile]
    end

    before do
      agent.set(tools:)
    end

    it do
      expect(Ractor.new(agent) { it.tools }.value).to eq(tools)
    end
  end
end
