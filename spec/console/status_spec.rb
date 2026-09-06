# frozen_string_literal: true

require "setup"
require "llm/console"

RSpec.describe LLM::Console::Status do
  let(:llm) { LLM.openai(key: "test") }
  let(:agent) { LLM::Agent.new(llm) }
  let(:console) { LLM::Console.new(agent:) }
  let(:status) { described_class.new(console) }
  let(:ctx) { agent.instance_variable_get(:@ctx) }

  describe "#context_bar" do
    context "when the agent is compacted" do
      before { ctx.compacted = true }

      it "renders an unknown bar" do
        expect(status.context_bar).to eq("│██████████│ ???")
      end
    end

    context "when the agent is not compacted" do
      before do
        ctx.messages << LLM::Message.new("user", "hi")
        ctx.messages << LLM::Message.new("assistant", "hi", usage: LLM::Object.from(total_tokens: 100))
      end

      it "renders the remaining usage" do
        expect(status.context_bar).to include("%")
      end
    end
  end

  describe "#nodes" do
    context "when the agent is compacted" do
      before { ctx.compacted = true }

      it "announces the compaction" do
        expect(status.nodes.map(&:text)).to eq(["Context compacted"])
      end
    end

    context "when the agent is not compacted" do
      it "shows the current status text" do
        status.text = "thinking…"
        expect(status.nodes.map(&:text)).to eq(["thinking…"])
      end
    end
  end

  describe "#model" do
    it "returns the agent's current model as a node" do
      expect(status.model.text).to eq(agent.model.to_s)
    end
  end

  describe "#cwd" do
    it "returns the working directory as a node" do
      expect(status.cwd.text).to eq(Dir.pwd.sub(Dir.home, "~"))
    end
  end
end
