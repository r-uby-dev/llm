# frozen_string_literal: true

require "setup"

##
# A request that is interrupted still closes its span.
#
# The tracer is told when a request starts, and an interrupt used to be
# the one way out of a request that told it nothing - so a tracer that
# draws what it is told drew a request that never ended, which reads the
# same as a process that died.
#
# Both paths are here because they are two different exceptions. A
# Net::HTTP request fails when its socket is closed from another thread,
# so the transport's own error is what arrives and the flag is what says
# why. Curb raises `LLM::Interrupt` from the chunk it is reading, and
# never reaches that rescue at all.
RSpec.describe "an interrupted request" do
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

    it "reports the interrupt to the tracer" do
      expect(errors.size).to eq(1)
    end

    it "reports the exception the caller is given" do
      raised = nil
      begin
        request
      rescue LLM::Interrupt => ex
        raised = ex
      end
      expect(reported).to be(raised)
    end

    it "names the request that ended" do
      expect(errors.last.at(1)).to eq(start_id)
    end

    it "reports an ending instead of a finish" do
      expect(tracer.calls.map(&:first)).to eq([:start, :error])
    end
  end

  describe "when the transport raises the interrupt itself" do
    before do
      request
    rescue LLM::Interrupt
      nil
    end

    it "reports the interrupt to the tracer" do
      expect(errors.size).to eq(1)
    end

    it "hands the tracer the interrupt the transport raised" do
      expect(reported).to be(failure)
    end

    it "names the request that ended" do
      expect(errors.last.at(1)).to eq(start_id)
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

    it "raises what the transport raised" do
      expect { request }.to raise_error(IOError)
    end
  end
end
