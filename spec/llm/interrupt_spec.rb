# frozen_string_literal: true

require "setup"

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
        allow(agent).to receive(:interrupt!).and_call_original
        registry.enter(agent)
        interrupted
      end

      after { registry.exit(agent) }

      it { is_expected.to be(agent) }

      it "returns the agent it interrupted" do
        expect(interrupted).to have_received(:interrupt!)
      end

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
