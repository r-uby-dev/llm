# frozen_string_literal: true

require "setup"

RSpec.describe LLM::Interrupt do
  let(:interrupt) { described_class.new("agent interrupted") }

  describe "what it is" do
    it "is an exception" do
      expect(described_class).to be < Exception
    end

    it "is not a signal" do
      expect(described_class).not_to be < SignalException
    end

    it "is not an error a broad rescue catches" do
      expect(interrupt).not_to be_a(StandardError)
    end

    it "can be raised without a message" do
      expect { raise LLM::Interrupt }.to raise_error(described_class)
    end

    it "carries the message it was raised with" do
      expect(interrupt.message).to eq("agent interrupted")
    end
  end

  describe "a rescue that catches everything" do
    let(:barely) do
      proc do |&block|
        block.call
      rescue
        :caught
      else
        :passed
      end
    end

    let(:broadly) do
      proc do |&block|
        block.call
      rescue
        :caught
      else
        :passed
      end
    end

    it "catches an ordinary error" do
      expect(barely.call { raise "boom" }).to eq(:caught)
    end

    it "catches an error a rescue of StandardError names" do
      expect(broadly.call { raise "boom" }).to eq(:caught)
    end

    it "does not catch an interrupt" do
      expect { barely.call { raise LLM::Interrupt } }
        .to raise_error(described_class)
    end

    it "does not catch an interrupt when it names StandardError" do
      expect { broadly.call { raise LLM::Interrupt } }
        .to raise_error(described_class)
    end
  end
end
