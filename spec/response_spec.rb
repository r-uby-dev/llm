# frozen_string_literal: true

require "setup"

RSpec.describe LLM::Response do
  let(:http_response) { Struct.new(:body).new(body) }
  let(:response) { described_class.new(http_response) }

  context "when the body includes an id" do
    let(:body) { LLM::Object.from(id: "res_123") }

    it "returns the id" do
      expect(response.id).to eq("res_123")
    end
  end

  context "when the body includes responseId" do
    let(:body) { LLM::Object.from(responseId: "google-response-123") }

    it "returns the response id" do
      expect(response.id).to eq("google-response-123")
    end
  end

  context "when the body includes request_id" do
    let(:body) { LLM::Object.from(request_id: "request-123") }

    it "returns the request id" do
      expect(response.id).to eq("request-123")
    end
  end

  context "when the body includes more than one id shape" do
    let(:body) { LLM::Object.from(id: "res_123", request_id: "request-123") }

    it "prefers id" do
      expect(response.id).to eq("res_123")
    end
  end

  context "when the body does not include an id" do
    let(:body) { LLM::Object.from(model: "test") }

    it "returns nil" do
      expect(response.id).to be_nil
    end
  end

  context "when the body is not an object" do
    let(:body) { "ok" }

    it "returns nil" do
      expect(response.id).to be_nil
    end
  end
end
