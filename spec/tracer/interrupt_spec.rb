# frozen_string_literal: true

require "setup"

##
# The tracer's interrupt hook, at the tool end.
#
# A request interrupt is announced by the transport, once. A tool is a
# different shape: a cancel reaches every tool that is running and the
# caller hears one exception, so the announcement belongs to the phase
# rather than to a tool - and `Context#wait` is where it is made, because
# that is the one frame every strategy's interrupt unwinds through.
#
# The tool sleeps, so the interrupt lands while it is running and the
# caller is inside `wait`. That is the same arrangement the interrupt
# examples in `spec/context_spec.rb` use, with a tracer watching.
RSpec.describe "the tracer's interrupt hook" do
  let(:provider) { LLM.openai(key: "test") }
  let(:model) { "gpt-5.4" }
  let(:ctx) { LLM::Context.new(provider, model:, tools: [tool]) }
  let(:tracer) { recorder.new(provider) }
  let(:recorder) do
    Class.new(LLM::Tracer) do
      attr_reader :calls

      def initialize(...)
        super
        @calls = []
      end

      def on_tool_start(id:, name:, arguments:, model:)
        nil
      end

      def on_tool_finish(result:, span:)
        nil
      end

      def on_interrupt(scope:, span: nil, request_id: nil)
        @calls << [:interrupt, scope]
        nil
      end
    end
  end

  before do
    fn = tool.function
    fn.id = "call_1"
    fn.arguments = {}
    ctx.messages << LLM::Message.new("assistant", nil, {
      tools: [tool],
      tool_calls: [{id: fn.id, name: fn.name, arguments: {}}]
    })
    ctx.tracer = tracer
  end

  describe "when the tool is interrupted while the caller waits" do
    let(:tool) do
      Class.new(LLM::Tool) do
        name "slow"

        def call
          sleep 10
          {ok: true}
        end
      end
    end

    it "announces the tool phase once" do
      thread = Thread.new do
        ctx.wait(:sequential)
      rescue LLM::Interrupt
        :interrupted
      end
      sleep 0.05
      ctx.interrupt!
      thread.join(2)
      expect(tracer.calls).to eq([[:interrupt, :tool]])
    end

    ##
    # The order is the point: the tracer has to be told while the tools
    # are still the work in flight, and what it had seen at the moment
    # the caller's rescue ran is the evidence of that.
    it "announces it before the caller is given the interrupt" do
      seen = nil
      thread = Thread.new do
        ctx.wait(:sequential)
      rescue LLM::Interrupt
        seen = tracer.calls.dup
      end
      sleep 0.05
      ctx.interrupt!
      thread.join(2)
      expect(seen).to eq([[:interrupt, :tool]])
    end
  end

  describe "when the tool answers" do
    let(:tool) do
      Class.new(LLM::Tool) do
        name "fast"

        def call
          {ok: true}
        end
      end
    end

    it "announces nothing" do
      ctx.wait(:sequential)
      expect(tracer.calls).to be_empty
    end
  end
end
