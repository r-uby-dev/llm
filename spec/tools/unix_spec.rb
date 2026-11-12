# frozen_string_literal: true

require "setup"
require "llm/tools/unix"

RSpec.describe LLM::Tool::Unix do
  describe ".abstract?" do
    it "returns true for the base class" do
      expect(described_class).to be_abstract
    end

    it "returns false for a tool below it" do
      expect(LLM::Tool::Unix::Man).to_not be_abstract
    end
  end

  describe ".name" do
    it "returns nil for the base class" do
      expect(described_class.name).to be_nil
    end
  end

  describe ".registry" do
    it "does not include the base class" do
      expect(LLM::Tool.registry).to_not include(described_class)
    end
  end

  describe ".subclasses" do
    it "does not include the base class" do
      expect(described_class.subclasses).to_not include(described_class)
    end

    it "returns the tools that depend on a unix command" do
      expect(described_class.subclasses.map(&:name)).to contain_exactly(
        "apropos", "find", "man", "mkdir"
      )
    end

    it "does not include tools that work on any platform" do
      names = described_class.subclasses.map(&:name)
      expect(names).to_not include("exec", "ls", "read-file", "write-file")
    end
  end

  describe "LLM::Tool.unix" do
    it "returns the unix tools" do
      expect(LLM::Tool.unix).to match_array(described_class.subclasses)
    end

    it "returns tools that live under the unix namespace" do
      expect(LLM::Tool.unix).to all(be <= described_class)
    end
  end
end
