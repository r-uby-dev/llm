# frozen_string_literal: true

require "setup"

RSpec.describe LLM::Utils do
  let(:uuid) { SecureRandom.uuid_v7 }
  let(:v4) { "9c7a3d1e-4b2f-4e6a-8c1d-2f5b7a9e3c4d" }

  describe ".uuidv7?" do
    let(:value) { uuid }
    let(:result) { LLM::Utils.uuidv7?(value) }

    it "is true for a UUIDv7" do
      expect(result).to be(true)
    end

    context "without hyphens" do
      let(:value) { uuid.delete("-") }

      it "is true" do
        expect(result).to be(true)
      end
    end

    context "for a UUID of another version" do
      let(:value) { v4 }

      it "is false" do
        expect(result).to be(false)
      end
    end

    context "for a string that is not a UUID" do
      let(:value) { "custom" }

      it "is false" do
        expect(result).to be(false)
      end
    end

    context "for nil" do
      let(:value) { nil }

      it "is false" do
        expect(result).to be(false)
      end
    end
  end

  describe ".timestamp" do
    let(:value) { uuid }
    let(:result) { LLM::Utils.timestamp(value) }

    it "reads the time out of a UUIDv7" do
      expect(result).to be_within(1).of(Time.now.utc)
    end

    context "for a UUID of another version" do
      let(:value) { v4 }

      it "is nil" do
        expect(result).to be_nil
      end
    end

    context "for a string that is not a UUID" do
      let(:value) { "custom" }

      it "is nil" do
        expect(result).to be_nil
      end
    end
  end
end
