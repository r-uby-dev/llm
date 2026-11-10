# frozen_string_literal: true

require "setup"
require "llm/tools/not_found"

RSpec.describe "LLM::Tool.NotFound" do
  let(:function) do
    LLM::Tool.NotFound(name: "nope").tap do |fn|
      fn.id = "call_1"
      fn.arguments = {}
    end
  end

  describe "#call" do
    it "returns the error in band" do
      expect(function.task(:sequential).wait).to be_error
    end
  end

  describe "under Ractor concurrency" do
    it "builds a class that can be made shareable" do
      expect(Ractor.shareable?(Ractor.make_shareable(function.runner))).to be(true)
    end

    it "returns the error in band" do
      expect(function.task(:ractor).wait).to be_error
    end

    it "names the error after the missing tool" do
      expect(function.task(:ractor).wait.value[:type]).to eq("LLM::NoSuchToolError")
    end

    it "reports the tool name the model asked for" do
      expect(function.task(:ractor).wait.value[:message]).to include("nope")
    end
  end
end
