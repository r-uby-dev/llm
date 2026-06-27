# frozen_string_literal: true

require "setup"

RSpec.describe "LLM::DeepInfra: embeddings" do
  let(:deepinfra) { LLM.deepinfra(key:) }
  let(:key) { ENV["DEEPINFRA_SECRET"] || "TOKEN" }

  context "when given a successful response",
          vcr: {cassette_name: "deepinfra/embeddings/successful_response"} do
    subject(:response) { deepinfra.embed("Hello, world") }

    it "returns an embedding" do
      expect(response).to be_instance_of(LLM::Response)
    end

    it "returns a model" do
      expect(response.model).to eq("BAAI/bge-m3")
    end

    it "has embeddings" do
      expect(response.embeddings).to be_instance_of(Array)
    end
  end
end
