# frozen_string_literal: true

require "setup"

RSpec.describe "LLM::Skill: openai",
               vcr: {cassette_name: "openai/chat/skill_check_date_natural"} do
  class SystemTool < LLM::Tool
    name "system"
    description "Runs system commands"
    params { it.object(command: it.string.required) }
    def call(command:)
      {success: true, output: "2025-08-24"}
    end
  end

  let(:key) { ENV["OPENAI_SECRET"] || "TOKEN" }
  let(:provider) { LLM.openai(key:) }
  let(:skill_path) { File.join(__dir__, "..", "skills", "check_date") }
  let(:ctx) { LLM::Context.new(provider, model: "gpt-4.1", skills: [skill_path]) }
  let(:agent_class) do
    skill_path = self.skill_path
    Class.new(LLM::Agent) do
      model "gpt-4.1"
      skills skill_path
    end
  end
  let(:agent) { agent_class.new(provider) }
  let(:prompt) { "What's today's date?" }

  around do |example|
    LLM::Tool.clear_registry!
    LLM::Tool.register(SystemTool)
    example.run
    LLM::Tool.clear_registry!
  end

  before do
    allow(Kernel).to receive(:system).with("date").and_return("2025-08-24")
  end

  describe "through LLM::Context" do
    subject(:result) do
      ctx.talk(prompt)
      ctx.talk(ctx.pending_functions.map(&:call))
    end

    it "runs a real skill directory through the tool loop" do
      expect(result.content).to include("Today's date is August 24, 2025.")
      expect(ctx.messages.select(&:tool_return?).size).to eq(1)
    end
  end

  describe "through LLM::Agent" do
    subject(:result) { agent.talk(prompt) }

    it "runs a real skill directory through the automatic tool loop" do
      expect(result.content).to include("Today's date is August 24, 2025.")
      expect(agent.messages.select(&:tool_return?).size).to eq(1)
    end
  end
end
