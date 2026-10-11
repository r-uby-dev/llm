# frozen_string_literal: true

require "setup"

##
# `LLM.interrupt`, and the shape of a wait.
#
# The registry is local to a process - that is the premise of the wait, not a
# limitation of it - and what is worth pinning is the count of looks and the
# count of sleeps. A loop like this one goes wrong in the guard, and there are
# two ways: looking once and giving up, or sleeping after the last look.
#
# The agent and the registry are both real. An agent entered into the registry
# with no turn running is the case `LLM::Context#interrupt!` already covers -
# no caller was recorded, so nothing is raised into the canceller - and it is
# the case this method meets when the turn it was waiting for is gone.
RSpec.describe LLM do
  describe ".interrupt" do
    let(:llm) { LLM.openai(key: "test") }
    let(:agent) { LLM::Agent.new(llm, model: "gpt-5.4") }
    let(:registry) { LLM::Agent.registry }

    before { allow(LLM).to receive(:sleep) }

    describe "an agent that is running" do
      subject(:interrupted) { LLM.interrupt(agent:) }

      before do
        allow(registry).to receive(:find).and_call_original
        registry.enter(agent)
        interrupted
      end

      after { registry.exit(agent) }

      it { is_expected.to be(true) }

      it "looks once, because attempts is 1 by default" do
        expect(registry).to have_received(:find).once
      end

      it "does not sleep, because the first look found it" do
        expect(LLM).not_to have_received(:sleep)
      end
    end

    describe "an agent that is not there" do
      subject(:interrupted) { LLM.interrupt(id: "no-such-row", attempts:, interval:) }

      let(:attempts) { 1 }
      let(:interval) { 0.1 }

      before do
        allow(registry).to receive(:find).and_return(nil)
        interrupted
      end

      context "with attempts left at 1" do
        it { is_expected.to be(false) }

        it "looks once" do
          expect(registry).to have_received(:find).once
        end

        it "does not sleep" do
          expect(LLM).not_to have_received(:sleep)
        end
      end

      context "with attempts above 1" do
        let(:attempts) { 5 }

        it { is_expected.to be(false) }

        it "looks attempts times" do
          expect(registry).to have_received(:find).exactly(5).times
        end

        it "sleeps between attempts and not after the last one" do
          expect(LLM).to have_received(:sleep).with(0.1).exactly(4).times
        end
      end
    end
  end
end
