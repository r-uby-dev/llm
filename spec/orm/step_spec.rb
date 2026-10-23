# frozen_string_literal: true

require "setup"
require "active_record"
require "sequel"
require "sqlite3"
require "llm/active_record"
require "sequel/plugins/agent"

RSpec.describe LLM::Step do
  let(:stream) { LLM::Stream.try(LLM::Stream.new) }
  let(:provider) { LLM.openai(key: "secret") }

  before do
    ctx.messages << LLM::Message.new("assistant", "hello")
    stream.on_step(ctx, nil)
  end

  context "with an ActiveRecord model" do
    let(:model) { LLM::Test::Harness.build_active_record_model(:spec_active_record_agents) }
    let(:agent) do
      Class.new(model) do
        acts_as_agent { |agent| agent.model "gpt-5.4-mini" }

        private

        def set_provider
          LLM.openai(key: "secret")
        end
      end
    end
    let(:record) { agent.create! }
    let(:reload_record) { ->(row) { row.class.find(row.id) } }
    let(:ctx) { LLM::Context.new(provider, record:, mode: :completions) }

    it "writes the conversation onto the record" do
      expect(reload_record.call(record).messages.last.content).to eq("hello")
    end
  end

  context "with a Sequel model" do
    let(:model) { LLM::Test::Harness.build_sequel_model(:spec_sequel_agents) }
    let(:agent) do
      Class.new(model) do
        plugin :agent do |agent|
          agent.model "gpt-5.4-mini"
        end

        private

        def set_provider
          LLM.openai(key: "secret")
        end
      end
    end
    let(:record) { agent.create }
    let(:reload_record) { ->(row) { row.class[row.id] } }
    let(:ctx) { LLM::Context.new(provider, record:, mode: :completions) }

    it "writes the conversation onto the record" do
      expect(reload_record.call(record).messages.last.content).to eq("hello")
    end
  end
end
