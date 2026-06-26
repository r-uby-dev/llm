# frozen_string_literal: true

require "setup"

RSpec.describe "LLM::Google::Models" do
  let(:key) { ENV["GOOGLE_SECRET"] || "TOKEN" }
  let(:provider) { LLM.google(key:) }

  context "when given a successful list operation",
          vcr: {cassette_name: "google/models/successful_list", match_requests_on: [:method]} do
    subject(:response) { provider.models.all }

    it "is successful" do
      is_expected.to be_instance_of(LLM::Response)
    end

    include_examples "LLM::Models contract"

    it "derives chat support from generation methods" do
      flash = response.models.find { _1.id == "gemini-2.5-flash" }
      non_chat = response.models.select { ["gemini-embedding-001", "imagen-4.0-generate-001"].include?(_1.id) }
      expect(flash).to be_a(LLM::Model)
      expect(non_chat.size).to eq(2)
      expect(flash.chat?).to be(true)
      expect(non_chat.none?(&:chat?)).to be(true)
    end
  end
end
