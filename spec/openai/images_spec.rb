# frozen_string_literal: true

require "setup"

RSpec.describe "LLM::OpenAI::Images" do
  let(:key) { ENV["OPENAI_SECRET"] || "TOKEN" }
  let(:provider) { LLM.openai(key:) }

  context "when given a successful create operation (base64)",
          vcr: {cassette_name: "openai/images/successful_create_base64"} do
    subject(:response) do
      provider.images.create(
        prompt: "A dog on a rocket to the moon"
      )
    end

    it "is successful" do
      expect(response).to be_instance_of(LLM::Response)
    end

    it "returns an array of images" do
      expect(response.images).to be_instance_of(Array)
    end

    it "returns an IO-like object" do
      expect(response.images[0]).to be_instance_of(StringIO)
    end
  end

  context "when given a successful edit",
        vcr: {cassette_name: "openai/images/successful_edit"} do
    subject(:response) do
      provider.images.edit(
        image: "spec/fixtures/images/bluebook.png",
        prompt: "Add white background"
      )
    end

    it "is successful" do
      expect(response).to be_instance_of(LLM::Response)
    end

    it "returns data" do
      expect(response.images).to be_instance_of(Array)
    end

    it "returns an IO-like object" do
      expect(response.images[0]).to be_instance_of(StringIO)
    end
  end
end
