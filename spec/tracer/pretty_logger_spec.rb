# frozen_string_literal: true

require "setup"
require "stringio"

##
# What the pretty logger writes, and what it hands back.
#
# The return value matters as much as the line: it is the span
# every ending is given, and a tracer that answers with the
# writer's own value leaves an interrupt with nothing to name
# the call that was cut.
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
    let(:span) { LLM::Object.from(id: "call_1", name: "tool") }
    let(:ex) { LLM::Interrupt.new }
    before { tracer.on_tool_interrupt(ex:, span:) }

    it "says the call was interrupted" do
      expect(io.string).to include("interrupted")
    end

    it "names the call that stopped" do
      expect(io.string).to include("tool (call_1)")
    end

    it "names the exception the caller was given" do
      expect(io.string).to include("LLM::Interrupt")
    end

    ##
    # A line with no call in it still says what happened,
    # which is what a tracer with no span is told.
    context "when the call was never started" do
      let(:span) { nil }

      it "writes the line without a call" do
        expect(io.string).to include("tool interrupted")
      end
    end
  end
end
