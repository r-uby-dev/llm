# frozen_string_literal: true

require "setup"

##
# An interrupt is a request to stop rather than a failure to handle, so it
# sits outside `StandardError`. The two rescue forms that catch nearly
# everything must not be able to swallow it: a turn whose cancel was eaten
# looks like a turn that ignored one.
#
# It is deliberately not a signal, either: a signal is a framework's own
# condition - RSpec re-raises one that escapes an example, and an async
# reactor ends its thread - and an interrupt has to be catchable.
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
    ##
    # Two shapes, and an interrupt has to come out of both: a bare rescue,
    # and the one that catches an error so it can carry on. Each is asked
    # for an ordinary error first, so that the examples below cannot pass
    # because the rescue was never a rescue.
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

    it "catches an ordinary error" do
      expect(barely.call { raise "boom" }).to eq(:caught)
    end

    it "catches an error a rescue of StandardError names" do
      expect(broadly.call { raise "boom" }).to eq(:caught)
    end

    ##
    # The claim itself: the rescue did not catch it, and the caller is
    # given it - which is the whole of what the class is for.
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
