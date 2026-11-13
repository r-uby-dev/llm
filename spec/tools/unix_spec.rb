# frozen_string_literal: true

require "setup"
require "llm/tools/unix"

RSpec.describe LLM::Tool::Unix do
  let(:subclasses) { described_class.subclasses }
  let(:names) { subclasses.map(&:name) }

  describe ".abstract?" do
    it "returns true for the namespace" do
      expect(described_class).to be_abstract
    end

    it "returns false for a tool below it" do
      expect(LLM::Tool::Unix::Man).to_not be_abstract
    end
  end

  describe ".name" do
    it "returns nil for the namespace" do
      expect(described_class.name).to be_nil
    end
  end

  describe ".registry" do
    it "does not include the namespace" do
      expect(LLM::Tool.registry).to_not include(described_class)
    end
  end

  describe ".subclasses" do
    it "does not include the namespace" do
      expect(subclasses).to_not include(described_class)
    end

    it "returns the tools that depend on a unix command" do
      expect(names).to contain_exactly("apropos", "find", "make", "man", "mkdir")
    end

    it "does not include exec" do
      expect(names).to_not include("exec")
    end

    it "does not include ls" do
      expect(names).to_not include("ls")
    end

    it "does not include read-file" do
      expect(names).to_not include("read-file")
    end

    it "does not include write-file" do
      expect(names).to_not include("write-file")
    end
  end

  describe "LLM::Tool.unix" do
    it "returns the unix tools" do
      expect(LLM::Tool.unix).to match_array(subclasses)
    end

    it "returns only tools below the namespace" do
      expect(LLM::Tool.unix).to all(be <= described_class)
    end
  end
end
