# frozen_string_literal: true

require "setup"
require "llm/tools/not-found"

RSpec.describe "LLM::Tool.NotFound" do
  let(:function) do
    LLM::Tool.NotFound(name: "nope").tap do |fn|
      fn.id = "call_1"
      fn.arguments = {}
    end
  end
  let(:tool) { function.runner }
  let(:sequential) { function.task(:sequential).wait }
  let(:ractor) { function.task(:ractor).wait }

  describe "#call" do
    it "returns the error in band" do
      expect(sequential).to be_error
    end
  end

  describe "under Ractor concurrency" do
    it "builds a class that can be made shareable" do
      expect(Ractor.shareable?(Ractor.make_shareable(tool))).to be(true)
    end

    it "returns the error in band" do
      expect(ractor).to be_error
    end

    it "raises NoSuchToolError" do
      expect(ractor.value[:type]).to eq("LLM::NoSuchToolError")
    end

    it "mentions the tool the model asked for" do
      expect(ractor.value[:message]).to include("nope")
    end
  end
end
