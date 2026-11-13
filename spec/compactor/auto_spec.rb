# frozen_string_literal: true

require "setup"

RSpec.describe LLM::Compactor::Auto do
  subject(:compactor) { described_class.new(ctx) }

  let(:provider) { LLM.openai(key: "test") }
  let(:ctx) { LLM::Context.new(provider, model: "gpt-5.4") }
  let(:window) { 10_000 }

  before { allow(ctx).to receive(:context_window).and_return(window) }

  def add_message(role, content, extra = {})
    ctx.messages << LLM::Message.new(role, content, extra)
  end

  ##
  # Adds a user message and the reply that follows it, so the conversation
  # grows the way a request reports it: each reply weighs more than the one
  # before it, and the growth between two replies is what the turns between
  # them added.
  def add_turn(content, usage)
    add_message "user", "#{content}?"
    add_message "assistant", content, {usage: {total_tokens: usage}}
  end

  describe "defaults" do
    it "compacts at five percent of the window" do
      expect(described_class::COMPACT_WHEN).to eq("5%")
    end

    it "keeps ten percent of the window" do
      expect(described_class::KEEP).to eq("10%")
    end
  end

  describe "#call" do
    context "when the context window is unknown" do
      let(:window) { nil }

      before { add_turn "first", 5_000 }

      it { expect(compactor.call).to be_nil }
    end

    context "when no request has reported usage" do
      before do
        add_message "user", "first"
        add_message "assistant", "second"
      end

      it { expect(compactor.call).to be_nil }
    end

    context "when the conversation is under compact_when" do
      before do
        add_message "user", "first"
        add_message "assistant", "second", {usage: {total_tokens: 400}}
      end

      it { expect(compactor.call).to be_nil }

      it "leaves the conversation alone" do
        expect { compactor.call }.not_to(change { ctx.messages.to_a })
      end
    end

    context "when the conversation passes compact_when" do
      before do
        add_turn "first", 1_000
        add_turn "second", 2_500
      end

      it "keeps the newest messages that weigh keep" do
        expect(compactor.call.map(&:content)).to eq(%w[second? second])
      end

      it "replaces the conversation with what it kept" do
        compactor.call
        expect(ctx.messages.map(&:content)).to eq(%w[second? second])
      end

      it "marks the context as compacted" do
        compactor.call
        expect(ctx.compacted?).to be(true)
      end
    end

    context "when the conversation is heavier than keep but only just" do
      before do
        add_turn "first", 300
        add_turn "second", 900
      end

      it { expect(compactor.call).to be_nil }
    end

    context "when the conversation has a system message" do
      before do
        add_message "system", "You are helpful"
        add_turn "first", 1_000
        add_turn "second", 2_500
      end

      it "keeps it" do
        compactor.call
        expect(ctx.messages.first.content).to eq("You are helpful")
      end

      it "returns the kept messages" do
        expect(compactor.call.map(&:content)).to eq(%w[second? second])
      end
    end

    context "when the thresholds are shares of the window" do
      before do
        add_turn "first", 2_000
        add_turn "second", 5_000
      end

      it "reads a percentage string" do
        result = compactor.call(compact_when: "20%", keep: "30%")
        expect(result.map(&:content)).to eq(%w[second? second])
      end

      it "reads an integer as a percentage" do
        result = compactor.call(compact_when: 20, keep: 30)
        expect(result.map(&:content)).to eq(%w[second? second])
      end

      it "reads a number below one as a fraction" do
        result = compactor.call(compact_when: 0.2, keep: 0.3)
        expect(result.map(&:content)).to eq(%w[second? second])
      end

      it "does nothing when the window is not full enough" do
        expect(compactor.call(compact_when: "90%")).to be_nil
      end
    end

    context "stream lifecycle" do
      let(:stream) { ctx.params[:stream] }
      let(:events) { [] }

      before do
        add_turn "first", 1_000
        add_turn "second", 2_500
        allow(stream).to receive(:on_compaction) { |c| events << [:start, c] }
        allow(stream).to receive(:on_compaction_finish) { |c| events << [:finish, c] }
      end

      it "emits the compaction lifecycle callbacks" do
        compactor.call
        expect(events).to eq([[:start, compactor], [:finish, compactor]])
      end
    end
  end
end
