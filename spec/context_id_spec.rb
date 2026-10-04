# frozen_string_literal: true

require "setup"

RSpec.describe "a context's id" do
  let(:llm) { LLM.openai(key: "secret") }
  let(:uuid) { SecureRandom.uuid_v7 }
  let(:id) { uuid }
  let(:record) { LLM::Test::Record.new(id) }
  let(:params) { {record:} }
  let(:ctx) { LLM::Context.new(llm, params) }

  context "when the context has no record" do
    let(:params) { {} }

    it "is a UUIDv7" do
      expect(LLM::Utils.timestamp(ctx.id)).not_to be_nil
    end
  end

  context "when the record's id is a UUIDv7" do
    it "is the record's id" do
      expect(ctx.id).to eq(uuid)
    end

    it "is the record's creation time" do
      expect(ctx.created_at).to eq(LLM::Utils.timestamp(uuid))
    end
  end

  context "when the record's id is not a UUIDv7" do
    let(:id) { 42 }

    it "is not the record's id" do
      expect(ctx.id).not_to eq(42)
    end

    it "is a UUIDv7" do
      expect(LLM::Utils.timestamp(ctx.id)).not_to be_nil
    end
  end

  context "when the record has no id yet" do
    let(:id) { nil }

    it "is a UUIDv7" do
      expect(LLM::Utils.timestamp(ctx.id)).not_to be_nil
    end
  end

  context "when an id is given" do
    let(:given) { SecureRandom.uuid_v7 }
    let(:params) { {id: given, record:} }

    it "is the id it was given, not the record's" do
      expect(ctx.id).to eq(given)
    end

    it "is the given id's creation time" do
      expect(ctx.created_at).to eq(LLM::Utils.timestamp(given))
    end
  end

  context "when the id that is given is not a UUIDv7" do
    let(:params) { {id: "custom"} }

    it "is refused" do
      expect { ctx }.to raise_error(LLM::Error, "an id must be a UUIDv7 string")
    end
  end

  ##
  # Through JSON, which is what a serialized payload is: `to_h` writes
  # symbol keys, and what a deserializer reads is a parsed payload, whose
  # keys are strings like the payload a record's column holds.
  context "when the context is restored" do
    let(:restored) { LLM::Context.new(llm).deserialize(string: ctx.to_json) }

    it "keeps the record's id" do
      expect(restored.id).to eq(uuid)
    end
  end
end
