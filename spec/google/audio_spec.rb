# frozen_string_literal: true

require "setup"

RSpec.describe "LLM::OpenAI::Audio" do
  let(:key) { ENV["GOOGLE_SECRET"] || "TOKEN" }
  let(:provider) { LLM.google(key:) }

  context "when given a successful transcription operation",
        vcr: {cassette_name: "google/audio/successful_transcription", match_requests_on: [:method]} do
    subject(:response) do
      provider.audio.create_transcription(file: "spec/fixtures/audio/rocket.mp3")
    end

    it "is successful" do
      expect(response).to be_a(LLM::Response)
    end

    it "returns a transcription" do
      expect(response.text.strip).to eq("A dog on a rocket to the moon.")
    end
  end

  context "when given a successful translation operation",
        vcr: {cassette_name: "google/audio/successful_translation", match_requests_on: [:method]} do
    subject(:response) { provider.audio.create_translation(file: "spec/fixtures/audio/bismillah.mp3") }
    let(:translation) { response.text.strip }
    let(:translations) do
      [
        "In the name of Allah, the Beneficent, the Merciful.",
        "In the name of God, the Most Gracious, the Most Merciful.",
        "In the name of Allah, the Most Compassionate, the Most Merciful.",
        "In the name of Allah, the Most Gracious, the Most Merciful."
      ]
    end

    it "is successful" do
      expect(response).to be_a(LLM::Response)
    end

    it "returns a translation" do
      expect(translations).to include(translation)
    end
  end
end
