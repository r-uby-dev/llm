# frozen_string_literal: true

require "setup"

RSpec.describe "request id" do
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
        @calls << [:error, request_id]
        nil
      end
    end
  end

  let(:transport) do
    double("transport", request_owner: :owner, interrupt_errors: [], interrupted?: false)
  end

  let(:start_id) { tracer.calls.find { it.first == :start }&.last }
  let(:finish_id) { tracer.calls.find { it.first == :finish }&.last }
  let(:error_id) { tracer.calls.find { it.first == :error }&.last }
  let(:ids) { tracer.calls.map(&:last) }

  before do
    provider.tracer = tracer
    allow(provider).to receive(:transport).and_return(transport)
    allow(transport).to receive(:set_body_stream)
    allow(transport).to receive(:request).and_return(response)
  end

  describe "when a request succeeds" do
    let(:payload) { {choices: [{message: {role: "assistant", content: "hi"}}]} }
    let(:response) do
      Net::HTTPOK.new("1.1", "200", "OK").tap do |res|
        allow(res).to receive(:body).and_return(LLM.json.dump(payload))
        allow(res).to receive(:[]).and_return("application/json")
      end
    end

    before { provider.complete([LLM::Message.new("user", "hi")], {model: "gpt-5.4"}) }

    it "mints a string" do
      expect(start_id).to be_a(String)
    end

    it "mints a UUIDv7" do
      expect(start_id).to match(/\A\h{8}-\h{4}-7\h{3}-\h{4}-\h{12}\z/)
    end

    it "passes the same id to the finish callback" do
      expect(finish_id).to eq(start_id)
    end

    it "mints a different id for the next request" do
      provider.complete([LLM::Message.new("user", "hi")], {model: "gpt-5.4"})
      expect(ids.uniq.size).to eq(2)
    end
  end

  describe "when a request fails" do
    let(:response) do
      Net::HTTPUnauthorized.new("1.1", "401", "Unauthorized").tap do |res|
        allow(res).to receive(:body).and_return("{}")
        allow(res).to receive(:[]).and_return("application/json")
      end
    end

    before do
      provider.complete([LLM::Message.new("user", "hi")], {model: "gpt-5.4"})
    rescue LLM::UnauthorizedError
      nil
    end

    it "passes the id to the error callback" do
      expect(error_id).to eq(start_id)
    end
  end
end
