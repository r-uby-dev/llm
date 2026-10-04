# frozen_string_literal: true

require "setup"

RSpec.describe "a context's id" do
  let(:llm) { LLM.openai(key: "secret") }
  let(:uuid) { SecureRandom.uuid_v7 }

  it "is a UUIDv7 when the context has no record" do
    ctx = LLM::Context.new(llm)
    expect(LLM::Utils.timestamp(ctx.id)).not_to be_nil
  end

  it "is the record's id when the record's id is a UUIDv7" do
    ctx = LLM::Context.new(llm, record: LLM::Test::Record.new(uuid))
    expect(ctx.id).to eq(uuid)
    expect(ctx.created_at).to eq(LLM::Utils.timestamp(uuid))
  end

  it "is generated when the record's id is not a UUIDv7" do
    ctx = LLM::Context.new(llm, record: LLM::Test::Record.new(42))
    expect(ctx.id).not_to eq(42)
    expect(LLM::Utils.timestamp(ctx.id)).not_to be_nil
  end

  it "is generated when the record has no id yet" do
    ctx = LLM::Context.new(llm, record: LLM::Test::Record.new(nil))
    expect(LLM::Utils.timestamp(ctx.id)).not_to be_nil
  end

  it "is the id it was given, whatever the record's is" do
    ctx = LLM::Context.new(llm, id: "custom", record: LLM::Test::Record.new(uuid))
    expect(ctx.id).to eq("custom")
    expect(ctx.created_at).to be_nil
  end

  it "survives a save and a restore" do
    ctx = LLM::Context.new(llm, record: LLM::Test::Record.new(uuid))
    restored = LLM::Context.new(llm).deserialize(data: ctx.to_h)
    expect(restored.id).to eq(uuid)
  end
end
