# frozen_string_literal: true

require "setup"
require "active_record"
require "sqlite3"
require "stringio"
require "llm/active_record"

RSpec.describe "acts_as_llm" do
  let(:model) { LLM::Test::Harness.build_active_record_model(:spec_active_record_llms) }

  let(:context) do
    Class.new(model) do
      acts_as_llm

      private

      def set_provider
        LLM.openai(key: "secret")
      end

      def set_context
        {model: "gpt-5.4-mini", mode: :responses, store: false}
      end

      def set_tracer
        LLM::Tracer::Logger.new(llm, io: StringIO.new)
      end
    end
  end

  let(:record) { context.create! }
  let(:reload_record) { ->(row) { row.class.find(row.id) } }
  let(:flush_record) { ->(row) { LLM::ActiveRecord::Utils.save!(row, row.send(:ctx), row.class.llm_plugin_options) } }

  include_examples "a persisted context record"

  context "with a live OpenAI completion",
          vcr: {cassette_name: "openai/chat/completion_contract"} do
    let(:context) do
      Class.new(model) do
        acts_as_llm

        private

        def set_provider
          LLM.openai(key: "secret")
        end

        def set_context
          {model: "gpt-4.1"}
        end

        def set_tracer
          LLM::Tracer::Logger.new(llm, io: StringIO.new)
        end
      end
    end

    let(:record) { context.create! }

    it "persists the returned messages" do
      result = record.talk("Hello, world!")
      expect(result).to be_a(LLM::Response)
      expect(reload_record.call(record).messages.last).to be_a(LLM::Message)
      expect(reload_record.call(record).messages.last.content).not_to be_empty
    end
  end
end
