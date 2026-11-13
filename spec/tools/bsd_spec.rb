# frozen_string_literal: true

require "setup"
require "llm/tools/bsd"

RSpec.describe LLM::Tool::BSD do
  let(:subclasses) { described_class.subclasses }
  let(:names) { subclasses.map(&:name) }

  describe ".abstract?" do
    it "returns true for the namespace" do
      expect(described_class).to be_abstract
    end

    it "returns false for a tool below it" do
      expect(LLM::Tool::BSD::Truss).to_not be_abstract
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

    it "returns the tools that depend on a BSD facility" do
      expect(names).to contain_exactly("pkg-install", "truss")
    end

    it "does not include a unix tool" do
      expect(names).to_not include("cc")
    end
  end

  describe "LLM::Tool.freebsd" do
    it "returns the BSD tools" do
      expect(LLM::Tool.freebsd).to match_array(subclasses)
    end

    it "returns only tools below the namespace" do
      expect(LLM::Tool.freebsd).to all(be <= described_class)
    end
  end
end
