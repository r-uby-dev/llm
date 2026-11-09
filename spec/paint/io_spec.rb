# frozen_string_literal: true

require "setup"

RSpec.describe LLM::Paint::IO do
  let(:io) { StringIO.new }

  before { LLM::Paint.enabled = true }
  after  { LLM::Paint.enabled = nil }

  describe "#write" do
    it "wraps text in the given colors" do
      described_class.new(io:, color: true).write("hello", :blue, :bold)
      expect(io.string).to eq("\e[34;1mhello\e[0m")
    end

    it "writes text unchanged when color is disabled" do
      described_class.new(io:, color: false).write("hello", :blue)
      expect(io.string).to eq("hello")
    end

    it "writes text unchanged when LLM::Paint is disabled" do
      LLM::Paint.enabled = false
      described_class.new(io:, color: true).write("hello", :blue)
      expect(io.string).to eq("hello")
    end

    it "writes text unchanged when it is given no colors" do
      described_class.new(io:, color: true).write("hello")
      expect(io.string).to eq("hello")
    end

    it "returns the number of bytes written" do
      expect(described_class.new(io:).write("hello")).to eq(5)
    end

    it "accepts text that is not a string" do
      described_class.new(io:, color: false).write(42)
      expect(io.string).to eq("42")
    end
  end

  describe "#color?" do
    around do |example|
      env = ENV.to_h
      ENV.delete("NO_COLOR")
      example.run
    ensure
      ENV.replace(env)
    end

    it "detects support from the wrapped IO when it was not set" do
      allow(io).to receive(:tty?).and_return(true)
      expect(described_class.new(io:).color?).to be(true)
    end

    it "returns false when the wrapped IO is not a terminal" do
      allow(io).to receive(:tty?).and_return(false)
      expect(described_class.new(io:).color?).to be(false)
    end

    it "returns false when $NO_COLOR is set" do
      allow(io).to receive(:tty?).and_return(true)
      ENV["NO_COLOR"] = "1"
      expect(described_class.new(io:).color?).to be(false)
    end

    it "returns the value it was set to" do
      color_io = described_class.new(io:, color: false)
      color_io.color = true
      expect(color_io.color?).to be(true)
    end
  end

  describe "#io" do
    it "returns the wrapped IO" do
      expect(described_class.new(io:).io).to be(io)
    end
  end
end
