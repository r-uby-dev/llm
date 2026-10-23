# frozen_string_literal: true

RSpec.shared_examples "LLM::Models contract" do
  it "returns normalized models" do
    expect(response.models).to all(be_a(LLM::Model))
  end

  it "iterates over normalized models" do
    expect(response.each).to be_a(Enumerator)
    expect(response.to_a).to all(be_a(LLM::Model))
  end

  it "supports collection accessors" do
    expect(response.size).to eq(response.models.size)
    expect(response[0]).to be_a(LLM::Model)
    expect(response.empty?).to be(false)
  end

  it "exposes common model fields" do
    model = response.models.first
    expect(model.id).to be_a(String)
    expect(model.name).to be_a(String)
    expect([true, false]).to include(model.chat?)
  end
end

