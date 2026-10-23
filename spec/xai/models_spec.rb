# frozen_string_literal: true

require "setup"

RSpec.describe "LLM::XAI::Models" do
  let(:key) { ENV["XAI_SECRET"] || "TOKEN" }
  let(:provider) { LLM.xai(key:) }

  context "when given a successful list operation",
          vcr: {cassette_name: "xai/models/successful_list"} do
    subject(:response) { provider.models.all }

    it "is successful" do
      is_expected.to be_instance_of(LLM::Response)
    end

    include_examples "LLM::Models contract"

    it "marks image-only models as not supporting chat" do
      image_models = response.models.select { it.id == "grok-2-image-1212" }
      expect(image_models.size).to eq(1)
      expect(image_models.none?(&:chat?)).to be(true)
    end
  end
end
