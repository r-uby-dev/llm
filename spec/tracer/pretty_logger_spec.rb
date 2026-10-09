# frozen_string_literal: true

require "setup"
require "stringio"

##
# What the pretty logger writes, and what it hands back.
#
# The return value matters as much as the line: it is the span
# every ending is given, and a tracer that answers with the
# writer's own value leaves an interrupt with nothing to name
# the call it ended.
RSpec.describe LLM::Tracer::PrettyLogger do
  let(:provider) { LLM.openai(key: "test") }
  let(:io) { StringIO.new }
  let(:tracer) { described_class.new(provider, io:) }

  describe "#on_tool_start" do
    let(:span) { tracer.on_tool_start(id: "call_1", name: "tool", arguments: {q: 1}) }
    before { span }

    it "returns a span the endings can name the call with" do
      expect(span.to_h).to eq({id: "call_1", name: "tool"})
    end

    it "writes the call it was given, as it always has" do
      expect(io.string).to include("tool(q: 1)")
    end
  end

  describe "#on_tool_interrupt" do
    let(:span) { LLM::Object.from(id: "call_abcdefghijkl", name: "slow") }
    let(:ex) { LLM::Interrupt.new }
    before { tracer.on_tool_interrupt(ex:, span:) }

    it "says the call received an interrupt" do
      expect(io.string).to include("received an interrupt")
    end

    it "names the tool that was running" do
      expect(io.string).to include("tool slow")
    end

    ##
    # An id is a long string that reads as gibberish, so the line
    # keeps the part that tells two of them apart.
    it "keeps ten characters of the call's id" do
      expect(io.string).to include("(call_abcde...)")
    end

    context "when the id is already short" do
      let(:span) { LLM::Object.from(id: "call_1", name: "slow") }

      it "leaves it whole" do
        expect(io.string).to include("(call_1)")
      end
    end
  end
end
