# frozen_string_literal: true

require "setup"

##
# The tracer's interrupt hooks, at the tool end.
#
# A request interrupt is announced by the transport, once. A tool is a
# different shape: a cancel reaches every tool that is running and the
# caller hears one exception, so the phase announcement belongs to the
# phase rather than to a tool - and `Context#wait` is where it is made,
# because that is the one frame every strategy's interrupt unwinds through.
#
# **And the call is announced as itself.** The same cancel that cuts the
# phase cuts calls, and a tracer that pairs a start with an ending needs the
# call's own: `on_tool_interrupt` is that ending, reached from
# `LLM::Function::Tracing`, which is the module above the strategy - so the
# tracer is told wherever the raise was issued from.
#
# The tool sleeps, so the interrupt lands while it is running and the caller
# is inside `wait`. That is the same arrangement the interrupt examples in
# `spec/context_spec.rb` and `spec/function/thread/task_spec.rb` use, with a
# tracer watching the call rather than the tool.
RSpec.describe "the tracer's interrupt hook" do
  let(:provider) { LLM.openai(key: "test") }
  let(:model) { "gpt-5.4" }
  let(:ctx) { LLM::Context.new(provider, model:, tools: [tool]) }
  let(:tracer) { recorder.new(provider) }
  let(:recorder) do
    Class.new(LLM::Tracer) do
      attr_reader :calls, :starts, :finishes, :interrupts

      def initialize(...)
        super
        @calls = []
        @starts = []
        @finishes = []
        @interrupts = []
      end

      def on_tool_start(id:, name:, arguments:, model:)
        span = "span:#{id}"
        @starts << span
        span
      end

      def on_tool_interrupt(ex:, span:)
        @interrupts << [ex, span]
        nil
      end

      def on_tool_finish(result:, span:)
        @finishes << span
        nil
      end

      def on_tool_error(ex:, span:)
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

  describe "when the call is cut" do
    let(:tool) do
      Class.new(LLM::Tool) do
        name "slow"

        def call
          sleep 10
          {ok: true}
        end
      end
    end

    let(:waited) do
      thread = Thread.new do
        ctx.wait(:thread)
      rescue LLM::Interrupt => ex
        ex
      end
      sleep 0.05
      ctx.interrupt!
      thread.join(2)
      thread.value
    end

    it "closes the call" do
      waited
      expect(tracer.interrupts.size).to eq(1)
    end

    it "hands it the span its start returned" do
      waited
      expect(tracer.interrupts.first.last).to equal(tracer.starts.first)
    end

    it "names the exception the caller was given" do
      given = waited
      expect(tracer.interrupts.first.first).to equal(given)
    end

    it "does not also announce a finish" do
      waited
      expect(tracer.finishes).to be_empty
    end

    it "still raises to the caller" do
      expect(waited).to be_a(LLM::Interrupt)
    end
  end

  describe "when a call answers" do
    let(:tool) do
      Class.new(LLM::Tool) do
        name "fast"

        def call
          {ok: true}
        end
      end
    end

    it "announces a finish rather than an interrupt" do
      ctx.wait(:thread)
      expect([tracer.finishes.size, tracer.interrupts.size]).to eq([1, 0])
    end
  end

  describe "when a call fails" do
    let(:tool) do
      Class.new(LLM::Tool) do
        name "failing"

        def call
          raise "no"
        end
      end
    end

    it "announces no interrupt" do
      ctx.wait(:thread)
      expect(tracer.interrupts).to be_empty
    end
  end
end
