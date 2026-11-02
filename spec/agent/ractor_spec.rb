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

  context "when given a tracer" do
    before do
      agent.set(tracer: LLM::Tracer::Null)
    end

    it "can access the tracer" do
      expect(Ractor.new { TestAgent.tracer }.value).to eq(LLM::Tracer::Null)
    end
  end

  context "when given a tool budget" do
    before do
      agent.set(tool_budget: 5)
    end

    it "can access the tool budget" do
      expect(Ractor.new { TestAgent.tool_budget }.value).to eq(5)
    end
  end

  context "when given a retry budget" do
    before do
      agent.set(retry_budget: 3)
    end

    it "can access the retry budget" do
      expect(Ractor.new { TestAgent.retry_budget }.value).to eq(3)
    end
  end

  context "when given a path" do
    before do
      agent.set(path: +"/tmp/test-agent")
    end

    it "can access the path" do
      expect(Ractor.new { TestAgent.path }.value).to eq("/tmp/test-agent")
    end
  end

  context "when given confirmations" do
    before do
      agent.set(confirm: %w[delete-file])
    end

    it "can access the confirmations" do
      expect(Ractor.new { TestAgent.confirm }.value).to eq(%w[delete-file])
    end
  end

  context "when given compactor options" do
    before do
      agent.set(compactor_options: {max_tokens: 10})
    end

    it "can access the compactor options" do
      expect(Ractor.new { TestAgent.compactor_options }.value).to eq(max_tokens: 10)
    end
  end

  context "when given a schema" do
    let(:schema) do
      {"type" => "object", "properties" => {"answer" => {"type" => "string"}}}
    end

    before do
      agent.set(schema:)
    end

    it "can access the schema" do
      expect(Ractor.new { TestAgent.schema }.value).to eq(schema)
    end
  end

  context "when given a schema class" do
    let(:schema) do
      stub_const("TestSchema", Class.new(LLM::Schema) do
        property :answer, LLM::Schema::String, "The answer"
      end)
    end

    before do
      agent.set(schema:)
    end

    it "can access the schema class" do
      expect(Ractor.new { TestAgent.schema }.value).to eq(schema)
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
