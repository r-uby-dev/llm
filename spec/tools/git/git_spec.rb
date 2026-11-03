# frozen_string_literal: true

require "setup"
require "llm/tools/git"

RSpec.describe LLM::Tool::Git do
  describe ".abstract?" do
    it "returns true for the base class" do
      expect(described_class).to be_abstract
    end

    it "returns false for a tool below it" do
      expect(LLM::Tool::Git::Log).to_not be_abstract
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
      expect(LLM::Tool.subclasses).to_not include(described_class)
    end

    it "returns the seven git tools" do
      expect(described_class.subclasses.map(&:name)).to contain_exactly(
        "git-branch", "git-checkout", "git-commit", "git-diff",
        "git-log", "git-show", "git-status"
      )
    end
  end
end
