# frozen_string_literal: true

require "setup"

RSpec.describe "a request that ends without answering" do
  let(:provider) { LLM.openai(key: "test") }
  let(:tracer) { recorder.new(provider) }
  let(:recorder) do
    Class.new(LLM::Tracer) do
      attr_reader :calls, :span

      def initialize(...)
        super
        @calls = []
        @span = Object.new
      end

      def on_request_start(operation:, model: nil, inputs: nil, request_id: nil)
        @calls << [:start, request_id]
        span
      end

      def on_request_finish(operation:, res:, model: nil, span: nil, outputs: nil, metadata: nil, request_id: nil)
        @calls << [:finish, request_id]
        nil
      end

      def on_request_error(ex:, span:, request_id: nil)
        @calls << [:error, request_id, ex]
        nil
      end

      def on_interrupt(scope:, span:, request_id: nil)
        @calls << [:interrupt, scope, request_id, span]
        nil
      end
    end
  end

  let(:interrupted) { true }
  let(:interrupt_errors) { [] }
  let(:failure) { LLM::Interrupt.new("request interrupted") }
  let(:transport) do
    double("transport",
      request_owner: :owner,
      interrupt_errors: interrupt_errors,
      interrupted?: interrupted)
  end

  let(:start_id) { tracer.calls.find { it.first == :start }&.at(1) }
  let(:errors) { tracer.calls.select { it.first == :error } }
  let(:reported) { errors.last&.at(2) }
  let(:endings) { tracer.calls.map(&:first) }
  let(:hooks) { tracer.calls.select { it.first == :interrupt } }
  let(:hooked) { hooks.last }
  let(:request) do
    provider.complete([LLM::Message.new("user", "hi")], {model: "gpt-5.4"})
  end

  before do
    provider.tracer = tracer
    allow(provider).to receive(:transport).and_return(transport)
    allow(transport).to receive(:set_body_stream)
    allow(transport).to receive(:request) { raise failure }
  end

  describe "when the transport fails because it was interrupted" do
    let(:interrupt_errors) { [IOError] }
    let(:failure) { IOError.new("closed stream") }

    before do
      request
    rescue LLM::Interrupt
      nil
    end

    it "raises an interrupt to the caller" do
      expect { request }.to raise_error(LLM::Interrupt)
    end

    it "calls on_interrupt once" do
      expect(hooks.size).to eq(1)
    end

    it "says which scope was interrupted" do
      expect(hooked.at(1)).to eq(:request)
    end

    it "names the request that was interrupted" do
      expect(hooked.at(2)).to eq(start_id)
    end

    it "hands the hook the span that was opened" do
      expect(hooked.at(3)).to be(tracer.span)
    end

    it "runs the hook before the caller is given the interrupt" do
      seen = []
      before = tracer.calls.size
      begin
        request
      rescue LLM::Interrupt
        seen = tracer.calls.drop(before).map(&:first)
      end
      expect(seen).to eq([:start, :interrupt])
    end

    it "does not report the interrupt as a request error" do
      expect(errors).to be_empty
    end

    it "reports the interrupt and nothing else" do
      expect(endings).to eq([:start, :interrupt])
    end
  end

  describe "when the transport raises the interrupt itself" do
    before do
      request
    rescue LLM::Interrupt
      nil
    end

    it "calls on_interrupt once" do
      expect(hooks.size).to eq(1)
    end

    it "says which scope was interrupted" do
      expect(hooked.at(1)).to eq(:request)
    end

    it "reports the interrupt and nothing else" do
      expect(endings).to eq([:start, :interrupt])
    end
  end

  describe "when the transport's own error is not an interrupt" do
    let(:interrupted) { false }
    let(:interrupt_errors) { [IOError] }
    let(:failure) { IOError.new("closed stream") }

    before do
      request
    rescue IOError
      nil
    end

    it "reports the failure to the tracer" do
      expect(reported).to be(failure)
    end

    it "does not call on_interrupt" do
      expect(hooks).to be_empty
    end

    it "raises what the transport raised" do
      expect { request }.to raise_error(IOError)
    end
  end

  describe "when the failure is not one of the transport's own" do
    let(:interrupted) { false }
    let(:interrupt_errors) { [IOError] }
    let(:failure) { Errno::ECONNREFUSED.new }

    before do
      request
    rescue SystemCallError
      nil
    end

    it "reports the failure to the tracer" do
      expect(reported).to be(failure)
    end

    it "reports an ending instead of a finish" do
      expect(endings).to eq([:start, :error])
    end

    it "does not call on_interrupt" do
      expect(hooks).to be_empty
    end

    it "raises what the transport raised" do
      expect { request }.to raise_error(Errno::ECONNREFUSED)
    end
  end
end
