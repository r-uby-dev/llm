# frozen_string_literal: true

require "setup"
require "fileutils"
require "tmpdir"

RSpec.describe LLM::Agent, "instructions" do
  let(:provider) { LLM.openai(key: "test") }
  let(:tmpdir) { Dir.mktmpdir("llmrb-instructions") }

  after { FileUtils.remove_entry(tmpdir) }

  def agent(instructions: "You are helpful", **params)
    described_class.new(provider, instructions:, **params)
  end

  def message(content, marked: true, role: "system")
    LLM::Message.new(role, content, marked ? {instructions: true} : {})
  end

  describe "#refresh_instructions!" do
    it "replaces a message whose instructions are out of date" do
      a = agent(instructions: "Say more")
      a.messages.concat [message("Say less")]
      a.send(:refresh_instructions!)
      expect(a.messages.first.content).to eq("Say more")
    end

    it "leaves a message that already says the right thing" do
      a = agent(instructions: "Say more")
      msg = message("Say more")
      a.messages.concat [msg]
      a.send(:refresh_instructions!)
      expect(a.messages.first).to be(msg)
    end

    it "leaves a message the agent did not write" do
      a = agent(instructions: "Say more")
      a.messages.concat [message("Earlier task context", marked: false)]
      a.send(:refresh_instructions!)
      expect(a.messages.first.content).to eq("Earlier task context")
    end

    it "keeps the mark on the message it writes" do
      a = agent(instructions: "Say more")
      a.messages.concat [message("Say less")]
      a.send(:refresh_instructions!)
      expect(a.messages.first.extra.key?(:instructions)).to be(true)
    end

    it "leaves a conversation alone when there are no instructions" do
      a = agent(instructions: nil)
      a.messages.concat [message("Say less")]
      a.send(:refresh_instructions!)
      expect(a.messages.first.content).to eq("Say less")
    end
  end

  describe "#apply_instructions" do
    it "refreshes the stored instructions on the way through" do
      a = agent(instructions: "Say more")
      a.messages.concat [message("Say less")]
      a.send(:apply_instructions, "hello")
      expect(a.messages.first.content).to eq("Say more")
    end

    it "leaves a prompt's own system message alone" do
      a = agent(instructions: "Say more")
      a.messages.concat [message("Say less")]
      a.send(:apply_instructions, a.prompt { it.system("The caller's rule") })
      expect(a.messages.first.content).to eq("Say less")
    end
  end

  describe "the round trip" do
    it "keeps the mark through a save and a restore" do
      path = File.join(tmpdir, "state.json")
      a = agent(instructions: "Say more")
      a.messages.concat [message("Say less")]
      a.serialize(path:)
      expect(agent(instructions: "Say more", path:).messages.first.extra.key?(:instructions)).to be(true)
    end

    it "refreshes a conversation that came back from a restore" do
      path = File.join(tmpdir, "state.json")
      a = agent(instructions: "Say more")
      a.messages.concat [message("Say less")]
      a.serialize(path:)
      restored = agent(instructions: "Say even more", path:)
      restored.send(:refresh_instructions!)
      expect(restored.messages.first.content).to eq("Say even more")
    end
  end

  describe "a provider whose instructions are not a system message" do
    let(:provider) { LLM.google(key: "test") }

    it "refreshes the message it wrote" do
      a = agent(instructions: "Say more")
      a.messages.concat [message("Say less", role: "user")]
      a.send(:refresh_instructions!)
      expect(a.messages.first.content).to eq("Say more")
    end

    it "keeps the role the message already had" do
      a = agent(instructions: "Say more")
      a.messages.concat [message("Say less", role: "user")]
      a.send(:refresh_instructions!)
      expect(a.messages.first.role).to eq("user")
    end

    it "leaves a caller's message alone" do
      a = agent(instructions: "Say more")
      a.messages.concat [LLM::Message.new("user", "Earlier task context")]
      a.send(:refresh_instructions!)
      expect(a.messages.first.content).to eq("Earlier task context")
    end
  end
end
