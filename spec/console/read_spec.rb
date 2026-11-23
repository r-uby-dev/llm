# frozen_string_literal: true

require "setup"
require "llm/console"

RSpec.describe LLM::Console do
  subject(:console) do
    agent = Class.new(LLM::Agent) do
      set name: "spec"
    end.new(LLM.openai(key: "test"))
    described_class.new(agent:)
  end

  let(:queue) { console.instance_variable_get(:@queue) }
  let(:redraws) { @redraws }

  before do
    @redraws = 0
    allow(console.window).to receive(:redraw) { @redraws += 1 }
    allow(console.buffer).to receive(:width).and_return(80)
    allow(console).to receive(:markdown).and_return([LLM::Console::Node.new("x")])
  end

  describe "#read!" do
    def enqueue(*messages)
      queue << [:start]
      messages.each { |message| queue << message }
      console.send(:read!)
      queue
    end

    it "drains the whole backlog in one call" do
      queue = enqueue(*Array.new(20) { |i| [:stream, "chunk #{i}"] })
      expect(queue).to be_empty
    end

    it "paints a run of chunks once" do
      enqueue(*Array.new(20) { |i| [:stream, "chunk #{i}"] })
      expect(redraws).to eq(1)
    end

    it "shows Thinking while the stream is running" do
      enqueue(*Array.new(3) { |i| [:stream, "chunk #{i}"] })
      expect(console.status.text).to eq(console.think_text)
    end

    it "ends the turn as soon as it is queued, backlog or not" do
      enqueue(*Array.new(20) { |i| [:stream, "chunk #{i}"] }, [:done, "final"])
      expect(console.status.text).to eq("idle")
    end
  end
end
