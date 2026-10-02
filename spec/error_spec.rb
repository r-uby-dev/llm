# frozen_string_literal: true

require_relative "setup"

##
# An interrupt is a request to stop rather than a failure to handle, so it
# is a signal and not an error. The two rescue forms that catch nearly
# everything must not be able to swallow it: a turn whose cancel was eaten
# looks like a turn that ignored one.
RSpec.describe LLM::Interrupt do
  let(:interrupt) { described_class.new("agent interrupted") }

  describe "what it is" do
    it "is a signal" do
      expect(described_class).to be < SignalException
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
    ##
    # Two shapes, and the interrupt passes both: a bare rescue, and the one
    # that catches an error so it can carry on.
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
      rescue StandardError
        :caught
      else
        :passed
      end
    end

    it "is not caught by a bare rescue" do
      expect(barely.call { raise LLM::Interrupt }).to eq(:passed)
    end

    it "is not caught by a rescue of StandardError" do
      expect(broadly.call { raise LLM::Interrupt }).to eq(:passed)
    end
  end
end
