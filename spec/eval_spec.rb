# frozen_string_literal: true

require "setup"
require "llm/eval"

RSpec.describe LLM::Eval do
  describe "#filter" do
    it "returns the block it was given" do
      block = proc {}
      evaluation = described_class.new
      evaluation.filter(&block)
      expect(evaluation.filter).to be(block)
    end

    it "returns nil when it was not given a block" do
      expect(described_class.new.filter).to be(nil)
    end

    it "evaluates the block into a message filter when the eval runs" do
      fake = double(:agent)
      evaluation = described_class.new do
        configure do
          agent { fake }
          filter do
            Class.new(LLM::MessageFilter) do
              def call(message:)
                message
              end
            end
          end
        end
      end
      evaluation.eval
      expect(evaluation.filter).to be < LLM::MessageFilter
    end
  end
end
