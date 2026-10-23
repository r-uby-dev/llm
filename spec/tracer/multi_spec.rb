# frozen_string_literal: true

require "setup"

RSpec.describe LLM::Tracer::Multi do
  let(:provider) { LLM.openai(key: "test") }
  let(:request_id) { SecureRandom.uuid_v7 }

  # A tracer that records every callback it receives and answers
  # start callbacks with a sentinel span.
  let(:recording_tracer_class) do
    Class.new(LLM::Tracer::Null) do
      attr_reader :calls

      def initialize(provider, span_prefix)
        super(provider)
        @span_prefix = span_prefix
        @calls = []
      end

      def on_request_start(operation:, request_id:, model: nil, inputs: nil)
        @calls << [:on_request_start, {operation:, model:, inputs:, request_id:}]
        "#{@span_prefix}:request"
      end

      def on_request_finish(operation:, res:, request_id:, model: nil, span: nil, outputs: nil, metadata: nil)
        @calls << [:on_request_finish, {operation:, model:, span:, outputs:, metadata:, request_id:}]
        nil
      end

      def on_request_error(ex:, span:, request_id:)
        @calls << [:on_request_error, {ex:, span:, request_id:}]
        nil
      end

      def on_tool_start(id:, name:, arguments:, model:)
        @calls << [:on_tool_start, {id:, name:, arguments:, model:}]
        "#{@span_prefix}:tool"
      end

      def on_tool_interrupt(ex:, span:, started_at:, finished_at:)
        @calls << [:on_tool_interrupt, {ex:, span:}]
        nil
      end

      def on_tool_finish(result:, span:, started_at:, finished_at:)
        @calls << [:on_tool_finish, {result:, span:}]
        nil
      end

      def on_tool_error(ex:, span:, started_at:, finished_at:)
        @calls << [:on_tool_error, {ex:, span:}]
        nil
      end

      def on_interrupt(scope:, span: nil, request_id: nil)
        @calls << [:on_interrupt, {scope:, span:, request_id:}]
        nil
      end

      def on_exit
        @calls << [:on_exit, {}]
        nil
      end

      def start_trace(**)
        @calls << [:start_trace, {}]
        self
      end

      def stop_trace
        @calls << [:stop_trace, {}]
        self
      end

      def set_finish_metadata_proc(proc)
        @calls << [:set_finish_metadata_proc, {}]
        self
      end

      def merge_extra(**)
        @calls << [:merge_extra, {}]
        self
      end
    end
  end

  let(:tracer_a) { recording_tracer_class.new(provider, "a") }
  let(:tracer_b) { recording_tracer_class.new(provider, "b") }
  let(:multi) { described_class.new(tracer_a, tracer_b) }

  describe "#initialize" do
    it "keeps the tracers" do
      expect(multi.tracers).to eq([tracer_a, tracer_b])
    end

    it "has no provider of its own" do
      expect(multi.llm).to be_nil
    end

    it "works with no tracers" do
      empty = described_class.new
      expect(empty.tracers).to eq([])
      expect {
        expect(empty.on_request_start(operation: "chat", request_id:)).to eq([])
      }.not_to raise_error
    end
  end

  describe ".multi" do
    let(:llm) { LLM.openai(key: "test") }

    let(:tracer_class) do
      Class.new(LLM::Tracer::Null) do
        attr_reader :calls

        def initialize(llm)
          super
          @calls = []
        end

        def on_request_start(operation:, request_id:, model: nil, inputs: nil)
          @calls << :on_request_start
          self
        end

        def on_interrupt(scope:, span: nil, request_id: nil)
          @calls << :on_interrupt
          nil
        end
      end
    end

    let(:first) { tracer_class.new(llm) }
    let(:second) { tracer_class.new(llm) }
    let(:multi) { LLM::Tracer.multi(llm, tracer_class, tracer_class) }
    let(:spans) { multi.on_request_start(operation: "chat", request_id:) }

    it "builds one tracer per class given" do
      expect(multi.tracers.size).to eq(2)
    end

    it "builds a tracer of the class given" do
      expect(multi.tracers).to all(be_a(tracer_class))
    end

    it "builds every tracer with the provider" do
      expect(multi.tracers.map(&:llm)).to eq([llm, llm])
    end

    it "builds the built-in tracers as well" do
      expect(LLM::Tracer.multi(llm, LLM::Tracer::Null).tracers).to all(be_a(LLM::Tracer::Null))
    end

    it "keeps the tracers in the order they are given" do
      expect(LLM::Tracer.multi(llm, first, second).tracers).to eq([first, second])
    end

    it "uses a tracer that is already an instance as it is" do
      expect(LLM::Tracer.multi(llm, first).tracers.first).to be(first)
    end

    it "builds a class given beside an instance" do
      expect(LLM::Tracer.multi(llm, first, tracer_class).tracers.last).to be_a(tracer_class)
    end

    it "holds no tracers when none are given" do
      expect(LLM::Tracer.multi(llm).tracers).to eq([])
    end

    it "returns no spans when it holds no tracers" do
      expect(LLM::Tracer.multi(llm).on_request_start(operation: "chat", request_id:)).to eq([])
    end

    it "returns the span each tracer answered with" do
      expect(spans).to eq(multi.tracers)
    end

    it "fans an interrupt out to every tracer" do
      multi.on_interrupt(scope: :request)
      expect(multi.tracers.map(&:calls)).to eq([[:on_interrupt], [:on_interrupt]])
    end
  end

  describe "#on_request_start / #on_request_finish" do
    let(:res) { double("LLM::Response") }

    it "fans out and returns one span per tracer, in order" do
      spans = multi.on_request_start(operation: "chat", model: "gpt-4.1", request_id:)
      expect(spans).to eq(["a:request", "b:request"])

      multi.on_request_finish(operation: "chat", model: "gpt-4.1", res:, span: spans, request_id:)

      finish_a = tracer_a.calls.find { |name,| name == :on_request_finish }
      finish_b = tracer_b.calls.find { |name,| name == :on_request_finish }
      expect(finish_a[1][:span]).to eq("a:request")
      expect(finish_b[1][:span]).to eq("b:request")
    end

    it "fans out request errors with the matching span" do
      spans = multi.on_request_start(operation: "chat", request_id:)
      ex = RuntimeError.new("boom")
      multi.on_request_error(ex:, span: spans, request_id:)

      error_b = tracer_b.calls.find { |name,| name == :on_request_error }
      expect(error_b[1][:ex]).to be(ex)
      expect(error_b[1][:span]).to eq("b:request")
    end
  end

  describe "#on_tool_start / #on_tool_finish" do
    let(:result) { LLM::Function::Return.new("call_1", "tool", {ok: true}) }

    it "fans out and returns one span per tracer, in order" do
      spans = multi.on_tool_start(id: "call_1", name: "tool", arguments: {q: 1}, model: "gpt-4.1")
      expect(spans).to eq(["a:tool", "b:tool"])

      multi.on_tool_finish(result:, span: spans, started_at: Time.now, finished_at: Time.now)

      finish_a = tracer_a.calls.find { |name,| name == :on_tool_finish }
      expect(finish_a[1][:span]).to eq("a:tool")
      expect(finish_a[1][:result]).to be(result)
    end

    it "fans out tool interrupts and tool errors with the matching span" do
      spans = multi.on_tool_start(id: "call_1", name: "tool", arguments: {}, model: "gpt-4.1")
      interrupt = LLM::Interrupt.new("stop")
      ex = RuntimeError.new("boom")

      expect { multi.on_tool_interrupt(ex: interrupt, span: spans, started_at: Time.now, finished_at: Time.now) }.not_to raise_error
      multi.on_tool_error(ex:, span: spans, started_at: Time.now, finished_at: Time.now)

      expect(tracer_a.calls.map(&:first)).to include(:on_tool_interrupt, :on_tool_error)
      error_a = tracer_a.calls.find { |name,| name == :on_tool_error }
      expect(error_a[1][:span]).to eq("a:tool")
    end
  end

  describe "#on_interrupt" do
    it "fans out with each tracer's own span" do
      spans = multi.on_request_start(operation: "chat", request_id:)
      multi.on_interrupt(scope: :request, span: spans, request_id:)

      interrupt_b = tracer_b.calls.find { |name,| name == :on_interrupt }
      expect(interrupt_b[1][:scope]).to eq(:request)
      expect(interrupt_b[1][:span]).to eq("b:request")
    end

    it "fans out without a span" do
      multi.on_interrupt(scope: :agent)
      expect(tracer_a.calls.map(&:first)).to include(:on_interrupt)
      interrupt_a = tracer_a.calls.find { |name,| name == :on_interrupt }
      expect(interrupt_a[1][:span]).to be_nil
    end
  end

  describe "a crashing tracer" do
    it "does not take the other tracers down with it" do
      # NB: defined on a subclass (not a singleton method) so the
      # inherited LLM::Tracer::Rescue wrapper applies, like it does
      # for every real tracer under Multi's supervision.
      crashing_class = Class.new(recording_tracer_class) do
        def on_request_start(**)
          raise "tracer exploded"
        end
      end
      crashing = crashing_class.new(provider, "x")
      multi = described_class.new(crashing, tracer_b)

      spans = nil
      expect {
        spans = multi.on_request_start(operation: "chat", request_id:)
      }.not_to raise_error
      # The crashed tracer contributes nil, in its position
      expect(spans).to eq([nil, "b:request"])
      expect(tracer_b.calls.map(&:first)).to include(:on_request_start)
    end

    it "lets LLM::Interrupt travel up the stack" do
      interrupting = recording_tracer_class.new(provider, "x")
      def interrupting.on_request_start(**)
        raise LLM::Interrupt, "stop"
      end
      multi = described_class.new(interrupting, tracer_b)

      expect {
        multi.on_request_start(operation: "chat", request_id:)
      }.to raise_error(LLM::Interrupt)
    end
  end

  describe "#on_exit" do
    it "fans out to every tracer" do
      multi.on_exit
      expect(tracer_a.calls.map(&:first)).to include(:on_exit)
      expect(tracer_b.calls.map(&:first)).to include(:on_exit)
    end
  end

  describe "#start_trace / #stop_trace" do
    it "fans out to every tracer" do
      multi.start_trace(name: "turn")
      multi.stop_trace
      expect(tracer_a.calls.map(&:first)).to include(:start_trace, :stop_trace)
      expect(tracer_b.calls.map(&:first)).to include(:start_trace, :stop_trace)
    end
  end

  describe "#set_finish_metadata_proc / #merge_extra" do
    it "fans out to every tracer" do
      proc = ->(res) { {intent: "chat"} }
      multi.set_finish_metadata_proc(proc)
      multi.merge_extra(metadata: {a: 1})
      expect(tracer_a.calls.map(&:first)).to include(:set_finish_metadata_proc, :merge_extra)
      expect(tracer_b.calls.map(&:first)).to include(:set_finish_metadata_proc, :merge_extra)
    end
  end
end
