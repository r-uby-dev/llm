# frozen_string_literal: true

require "setup"

##
# `LLM.interrupt`, and the shape of a wait.
#
# The method looks for an agent in this process's registry and interrupts it
# when it is there. Two things are worth pinning down: how many times it
# looks, and whether it sleeps after the last look that found nothing. The
# second is where a loop like this usually goes wrong, and it is the
# difference between waiting `attempts * interval` and waiting
# `(attempts - 1) * interval`.
#
# The examples stub the registry instead of entering an agent into it, since
# the registry is a singleton and an entry left behind would be found by
# whatever runs next.
RSpec.describe LLM do
  describe ".interrupt" do
    let(:row) { double(id: "a-row-id") }
    let(:agent) { double(record: row, id: "an-agent-id", interrupt!: nil) }

    before { allow(LLM).to receive(:sleep) }

    context "when the agent is running" do
      before { allow(LLM::Agent.registry).to receive(:find).and_return(agent) }

      it "interrupts it and answers true" do
        expect(LLM.interrupt(id: "a-row-id")).to be(true)
        expect(agent).to have_received(:interrupt!)
      end

      it "looks once when attempts is 1" do
        LLM.interrupt(id: "a-row-id")
        expect(LLM::Agent.registry).to have_received(:find).once
      end

      it "does not sleep, however many attempts it was given" do
        LLM.interrupt(id: "a-row-id", attempts: 3, interval: 0.1)
        expect(LLM).not_to have_received(:sleep)
      end
    end

    context "when it is not running" do
      before { allow(LLM::Agent.registry).to receive(:find).and_return(nil) }

      it "answers false" do
        expect(LLM.interrupt(id: "a-row-id")).to be(false)
      end

      it "looks once and does not sleep when attempts is 1" do
        LLM.interrupt(id: "a-row-id")
        expect(LLM::Agent.registry).to have_received(:find).once
        expect(LLM).not_to have_received(:sleep)
      end

      it "looks attempts times" do
        LLM.interrupt(id: "a-row-id", attempts: 5, interval: 0.1)
        expect(LLM::Agent.registry).to have_received(:find).exactly(5).times
      end

      it "sleeps between attempts and not after the last one" do
        LLM.interrupt(id: "a-row-id", attempts: 5, interval: 0.1)
        expect(LLM).to have_received(:sleep).with(0.1).exactly(4).times
      end
    end
  end
end
