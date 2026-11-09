# frozen_string_literal: true

require_relative "setup"

RSpec.describe LLM::Paint do
  before { described_class.enabled = true }
  after  { described_class.enabled = nil }

  describe ".[]" do
    it "returns the text unchanged when given no options" do
      expect(described_class["hello"]).to eq("hello")
    end

    it "sets a foreground color" do
      expect(described_class["hello", :blue]).to eq("\e[34mhello\e[0m")
    end

    it "combines a color with an effect" do
      expect(described_class["hello", :blue, :bold]).to eq("\e[34;1mhello\e[0m")
    end

    it "sets a background color" do
      expect(described_class["hello", :white, :on_red]).to eq("\e[37;41mhello\e[0m")
    end

    it "returns the text unchanged when color is disabled" do
      described_class.enabled = false
      expect(described_class["hello", :blue]).to eq("hello")
    end

    it "accepts text that is not a string" do
      expect(described_class[42, :red]).to eq("\e[31m42\e[0m")
    end

    it "raises an ArgumentError when an option is not a color or an effect" do
      expect { described_class["hello", :pink] }
        .to raise_error(ArgumentError, /unknown color or effect: :pink/)
    end
  end

  describe ".enabled?" do
    it "returns the value it was set to" do
      described_class.enabled = false
      expect(described_class.enabled?).to be(false)
    end
  end

  describe ".detect" do
    around do |example|
      env = ENV.to_h
      example.run
    ensure
      ENV.replace(env)
    end

    it "returns false when $NO_COLOR is set" do
      ENV["NO_COLOR"] = "1"
      allow($stdout).to receive(:tty?).and_return(true)
      expect(described_class.detect).to be(false)
    end

    it "returns false when standard output is not a terminal" do
      ENV.delete("NO_COLOR")
      allow($stdout).to receive(:tty?).and_return(false)
      expect(described_class.detect).to be(false)
    end

    it "returns true when $NO_COLOR is empty and standard output is a terminal" do
      ENV["NO_COLOR"] = ""
      allow($stdout).to receive(:tty?).and_return(true)
      expect(described_class.detect).to be(true)
    end
  end
end
