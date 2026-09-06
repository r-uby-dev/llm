# frozen_string_literal: true

require "setup"
require "llm/console"

RSpec.describe LLM::Console::Input::Char do
  let(:char) { described_class.new("a") }
  let(:same) { described_class.new("a") }
  let(:other) { described_class.new("b") }
  let(:empty) { described_class.new("") }

  describe "#==" do
    it "equals the wrapped string" do
      expect(char).to eq("a")
    end

    it "equals a char with the same character" do
      expect(char).to eq(same)
    end

    it "does not equal a char with a different character" do
      expect(char).not_to eq(other)
    end

    it "is not symmetric" do
      expect("a").not_to eq(char)
    end
  end

  describe "#eql?" do
    it "is true for the wrapped string" do
      expect(char.eql?("a")).to be(true)
    end

    it "is true for a char with the same character" do
      expect(char.eql?(same)).to be(true)
    end

    it "is false for a char with a different character" do
      expect(char.eql?(other)).to be(false)
    end
  end

  describe "#hash" do
    it "matches a char with the same character" do
      expect(char.hash).to eq(same.hash)
    end

    it "differs for a char with a different character" do
      expect(char.hash).not_to eq(other.hash)
    end
  end

  describe "#empty?" do
    it "is true for an empty char" do
      expect(empty).to be_empty
    end

    it "is false for a non-empty char" do
      expect(char).not_to be_empty
    end
  end

  describe "#to_s" do
    it "returns the wrapped string" do
      expect(char.to_s).to eq("a")
    end
  end
end
