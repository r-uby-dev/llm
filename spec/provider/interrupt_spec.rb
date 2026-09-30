# frozen_string_literal: true

require "setup"

##
# A request that ends without answering closes its span.
#
# The tracer is told when a request starts, and a request that failed was
# the one way out that told it nothing - so a tracer that draws what it is
# told drew a request that never ended, which reads the same as a process
# that died.
#
# An interrupt is the exception, and deliberately so: it is not a failure,
# and the tracer's own interrupt hook is what will close the span. Until
# that hook exists an interrupted request leaves its span open, and the
# examples below say so - so the change that lands the hook fails here
# first, rather than being a silence nobody notices.
#
# Four ways out, and three of them are here. A transport that failed
# because it was interrupted, a transport that raised the interrupt itself
# (curb raises from the chunk it is reading, so it never reaches the
# rescue for the transport's own error classes), a transport that failed
# for another reason, and a failure that is not one of those classes at
# all.
RSpec.describe "a request that ends without answering" do
  let(:provider) { LLM.openai(key: "test") }
  let(:tracer) { recorder.new(provider) }
  let(:recorder) do
    Class.new(LLM::Tracer) do
      attr_reader :calls

      def initialize(...)
        super
        @calls = []
      end

      def on_request_start(operation:, model: nil, inputs: nil, request_id: nil)
        @calls << [:start, request_id]
        nil
      end

      def on_request_finish(operation:, res:, model: nil, span: nil, outputs: nil, metadata: nil, request_id: nil)
        @calls << [:finish, request_id]
        nil
      end

      def on_request_error(ex:, span:, request_id: nil)
        @calls << [:error, request_id, ex]
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

  let(:start_id) { tracer.calls.find { _1.first == :start }&.at(1) }
  let(:errors) { tracer.calls.select { _1.first == :error } }
  let(:reported) { errors.last&.at(2) }
  let(:endings) { tracer.calls.map(&:first) }
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

    it "does not report the interrupt as a request error" do
      expect(errors).to be_empty
    end

    it "leaves the span for the interrupt hook to close" do
      expect(endings).to eq([:start])
    end
  end

  describe "when the transport raises the interrupt itself" do
    before do
      request
    rescue LLM::Interrupt
      nil
    end

    it "does not report the interrupt as a request error" do
      expect(errors).to be_empty
    end

    it "leaves the span for the interrupt hook to close" do
      expect(endings).to eq([:start])
    end
  end

  describe "when the transport fails for another reason" do
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

    it "names the request that ended" do
      expect(errors.last.at(1)).to eq(start_id)
    end

    it "reports an ending instead of a finish" do
      expect(endings).to eq([:start, :error])
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

    it "raises what the transport raised" do
      expect { request }.to raise_error(Errno::ECONNREFUSED)
    end
  end
end
