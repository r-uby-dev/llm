# frozen_string_literal: true

require "setup"
require "sequel"
require "sqlite3"
require "stringio"
require "sequel/plugins/llm"

RSpec.describe "plugin :llm" do
  let(:model) { LLM::Test::Harness.build_sequel_model(:spec_sequel_llms) }

  let(:context) do
    Class.new(model) do
      plugin :llm

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

  let(:record) { context.create }
  let(:reload_record) { ->(row) { row.class[row.id] } }
  let(:flush_record) { ->(row) { LLM::Sequel::Plugin::Utils.save!(row, row.send(:ctx), row.class.llm_plugin_options) } }

  include_examples "a persisted context record"

  context "with a live OpenAI completion",
          vcr: {cassette_name: "openai/chat/completion_contract"} do
    let(:context) do
      Class.new(model) do
        plugin :llm

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

    let(:record) { context.create }

    it "persists the returned messages" do
      result = record.talk("Hello, world!")
      expect(result).to be_a(LLM::Response)
      expect(reload_record.call(record).messages.last).to be_a(LLM::Message)
      expect(reload_record.call(record).messages.last.content).not_to be_empty
    end

    context "with PostgreSQL jsonb storage" do
      before do
        reason = LLM::Test::Harness.postgres_unavailable_reason
        skip reason if reason
      end

      let(:model) do
        LLM::Test::Harness.build_sequel_model(
          :spec_sequel_llms_jsonb,
          adapter: :postgres,
          jsonb: true
        )
      end
      let(:context) do
        Class.new(model) do
          plugin :llm, format: :jsonb

          private

          def set_provider
            LLM.openai(key: "secret")
          end

          def set_context
            {model: "gpt-4.1"}
          end
        end
      end

      it "persists structured response data" do
        record.talk("Hello, world!")
        expect(reload_record.call(record)[:data]).to respond_to(:fetch)
        expect(reload_record.call(record).messages.last.content).not_to be_empty
      end
    end
  end
end
