# frozen_string_literal: true

require "setup"
require "llm/tools/ruby-lang"

RSpec.describe LLM::Tool::RubyLang do
  let(:subclasses) { described_class.subclasses }
  let(:names) { subclasses.map(&:name) }

  describe ".abstract?" do
    it "returns true for the namespace" do
      expect(described_class).to be_abstract
    end

    it "returns false for a tool below it" do
      expect(LLM::Tool::RubyLang::Issue).to_not be_abstract
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

    it "returns the tools that read bugs.ruby-lang.org" do
      expect(names).to contain_exactly(
        "ruby-lang-issue", "ruby-lang-issues", "ruby-lang-projects", "ruby-lang-search"
      )
    end
  end

  describe "LLM::Tool.rubylang" do
    it "returns the ruby-lang.org tools" do
      expect(LLM::Tool.rubylang).to match_array(subclasses)
    end

    it "returns only tools below the namespace" do
      expect(LLM::Tool.rubylang).to all(be <= described_class)
    end
  end
end
