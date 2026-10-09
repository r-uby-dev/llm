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
  let(:provider) { LLM::OpenAI.new }
  let(:io) { StringIO.new }
  let(:tracer) { described_class.new(provider, io:) }
  let(:openai) do
    Class.new do
      def initialize
        @host = "api.openai.com"
        @port = 443
      end
    end
  end

  before { stub_const("LLM::OpenAI", openai) }

  describe "#on_tool_start" do
    let(:span) { tracer.on_tool_start(id: "call_1", name: "tool", arguments: {q: 1}) }

    it "returns a span the endings can name the call with" do
      expect(span.to_h).to eq({id: "call_1", name: "tool"})
    end

    it "writes the call it was given, as it always has" do
      span
      expect(io.string).to include("tool(q: 1)")
    end
  end
end
