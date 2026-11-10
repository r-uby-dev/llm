# frozen_string_literal: true

require "setup"
require "stringio"

RSpec.describe LLM::Tracer::EnhancedLogger do
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
    before { tracer.on_tool_interrupt(ex:, span:, started_at: Time.now, finished_at: Time.now) }

    it "says the call received an interrupt" do
      expect(io.string).to include("received an interrupt")
    end

    it "names the tool that was running" do
      expect(io.string).to include("tool slow")
    end

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

  describe "#on_request_start" do
    before do
      tracer.on_request_start(operation: "chat", model: "gpt-4.1", request_id: "req_1")
    end

    it "writes the provider and the model it is about to call" do
      expect(io.string).to include("-> openai gpt-4.1")
    end

    it "opens the log with a rule" do
      expect(io.string).to start_with("---")
    end

    it "writes no escape sequences to an IO that is not a terminal" do
      expect(io.string).not_to include("\e[")
    end
  end

  describe "#on_exit" do
    let(:res) { double("LLM::Response", usage: double("LLM::Usage", input_tokens: 1200, output_tokens: 340)) }

    before do
      tracer.on_request_start(operation: "chat", model: "gpt-4.1", request_id: "req_1")
      tracer.on_request_finish(operation: "chat", res:, request_id: "req_1")
      tracer.on_tool_start(id: "call_1", name: "tool", arguments: {q: 1})
      tracer.on_exit
    end

    it "summarizes the requests" do
      expect(io.string).to include("requests   1")
    end

    it "summarizes the tools" do
      expect(io.string).to include("tool 1")
    end

    it "summarizes the tokens" do
      expect(io.string).to include("1.2k in / 340 out")
    end

    it "summarizes the time it took" do
      expect(io.string).to match(/time\s+\d+\.\d+s/)
    end
  end

  context "when the IO is a terminal" do
    before do
      allow(LLM::Paint).to receive(:detect).and_return(true)
      LLM::Paint.enabled = true
    end

    after { LLM::Paint.enabled = nil }

    it "writes color" do
      tracer.on_request_start(operation: "chat", model: "gpt-4.1", request_id: "req_1")
      expect(io.string).to include("\e[36m->\e[0m")
    end
  end
end
