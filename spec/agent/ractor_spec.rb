# frozen_string_literal: true

require "setup"
require "llm/providers/openai"
require "llm/tools"

RSpec.describe "LLM::Agent in a ractor" do
  let(:agent) { stub_const("TestAgent", Ractor.make_shareable(Class.new(LLM::Agent))) }

  context "when given the name" do

    it "derives a name for a class that never had one set" do
      expect(Ractor.new(agent) { TestAgent.name }.value).to eq("test-agent")
    end

    it "derives the same name on the main ractor" do
      expect(agent.name).to eq("test-agent")
    end
  end

  context "when given a description" do
    before do
      agent.set(description: +"described by the model")
    end

    it "can access the description" do
      expect(Ractor.new { TestAgent.description }.value).to eq("described by the model")
    end
  end

  context "when given a model" do
    before do
      agent.set(model: +"gpt-5.4-mini")
    end

    it "can access the model" do
      expect(Ractor.new { TestAgent.model }.value).to eq("gpt-5.4-mini")
    end
  end

  context "when given instructions" do
    before do
      agent.set(instructions: +"You are concise.")
    end

    it "can access the instructions" do
      expect(Ractor.new { TestAgent.instructions }.value).to eq("You are concise.")
    end
  end

  context "when given a concurrency" do
    before do
      agent.set(concurrency: :thread)
    end

    it "can access the concurrency" do
      expect(Ractor.new { TestAgent.concurrency }.value).to eq(:thread)
    end
  end

  context "when given a compactor" do
    before do
      agent.set(compactor: LLM::Compactor::Null)
    end

    it "can access the compactor" do
      expect(Ractor.new { TestAgent.compactor }.value).to eq(LLM::Compactor::Null)
    end
  end

  context "when given tools" do
    let(:tools) do
      [LLM::Tool::ReadFile]
    end

    before do
      agent.set(tools:)
    end

    it "can access the tools" do
      expect(Ractor.new { TestAgent.tools }.value).to eq(tools)
    end
  end
end
