# frozen_string_literal: true

require "setup"

RSpec.describe "LLM::Google::Images" do
  let(:key) { ENV["GOOGLE_SECRET"] || "TOKEN" }
  let(:provider) { LLM.google(key:) }

  context "when given a successful create operation",
        vcr: {cassette_name: "google/images/imagen_successful_create", match_requests_on: [:method]} do
    subject(:response) { provider.images.create(prompt: "A dog on a rocket to the moon") }

    it "is successful" do
      expect(response).to be_instance_of(LLM::Response)
    end

    it "returns one image" do
      expect(response.images.size).to eq(1)
    end

    it "returns an IO-like object" do
      expect(response.images.first).to be_instance_of(StringIO)
    end
  end

  context "when given an edit operation" do
    it "raises NotImplementedError" do
      expect do
        provider.images.edit(
          image: "spec/fixtures/images/bluebook.png",
          prompt: "Book is floating in the clouds"
        )
      end.to raise_error(NotImplementedError, /not yet supported/i)
    end
  end
end
