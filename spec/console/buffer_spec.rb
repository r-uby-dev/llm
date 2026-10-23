# frozen_string_literal: true

require "setup"
require "llm/console"

RSpec.describe LLM::Console::Buffer do
  let(:llm) { LLM.deepseek(key: "test") }
  let(:agent) { LLM::Agent.new(llm) }
  let(:console) { LLM::Console.new(agent:) }
  let(:buffer) { described_class.new(console) }

  before { allow(Curses).to receive(:cols).and_return(149) }

  describe "when given word wrap" do
    context "when given a string shorter than the width" do
      let(:string) do
        "Lorem ipsum dolor sit amet, consectetur adipiscing"
      end

      before { buffer.write(string) }

      it "keeps the whole string on a single row" do
        expect(rendered).to eq([string])
      end
    end

    context "when given a string longer than the width" do
      let(:string) do
        "Lorem ipsum dolor sit amet, consectetur adipiscing elit, " \
        "sed do eiusmod tempor incididunt ut labore et dolore magna " \
        "aliqua."
      end

      before { buffer.write(string) }

      it "moves whole words to the next line instead of cutting them" do
        expect(rendered).to eq([
          "Lorem ipsum dolor sit amet, consectetur adipiscing elit, sed do eiusmod tempor incididunt",
          "ut labore et dolore magna aliqua."
        ])
      end

      it "never lets a row exceed the width" do
        expect(rendered).to all(satisfy { |row| row.length <= 89 })
      end
    end

    it "keeps short text on a single row" do
      buffer.write("short")
      expect(rendered).to eq(["short"])
    end

    it "respects explicit newlines" do
      buffer.write("line one\nline two")
      expect(rendered).to eq(["line one", "line two"])
    end

    it "hard-breaks a single word longer than the width" do
      word = "x" * 200
      buffer.write(word)
      expect(rendered.join).to eq(word)
      expect(rendered).to all(satisfy { |row| row.length <= 89 })
    end
  end

  def rendered
    buffer.visible(100).map { |row| row.map { |chunk| chunk[:text] }.join }.reject(&:empty?)
  end

  describe "#open?" do
    it "returns false before the buffer is opened" do
      expect(buffer.open?).to be(false)
    end

    context "when the buffer has been opened" do
      before { buffer.open }

      it "returns true" do
        expect(buffer.open?).to be(true)
      end
    end

    context "when the buffer has been closed" do
      before do
        buffer.open
        buffer.close
      end

      it "returns false" do
        expect(buffer.open?).to be(false)
      end
    end
  end

  describe "#replace" do
    let(:chunks) { [LLM::Console::Node.new("hi")] }

    context "when the buffer has not been opened" do
      before { buffer.write(chunks, method: :replace) }

      it "keeps the text instead of raising" do
        expect(rendered).to include("hi")
      end
    end
  end

  describe "spacer row" do
    subject(:rows) { buffer.visible(100).map { |row| row.map { |chunk| chunk[:text] }.join } }

    before { buffer.write("first") }

    it "keeps a leading empty row above the first message" do
      expect(rows[0]).to eq("")
    end

    it "places the first message below the spacer" do
      expect(rows[1]).to eq("first")
    end
  end
end
