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
      plugin(:llm, tracer: -> { LLM::Tracer.logger(llm, io: StringIO.new) })

      private

      def set_provider
        LLM.openai(key: "secret")
      end

      def set_context
        {model: "gpt-5.4-mini", mode: :responses, store: false}
      end
    end
  end

  let(:record) { context.create }
  let(:reload_record) { ->(row) { row.class[row.id] } }
  let(:flush_record) { ->(row) { LLM::Sequel::Plugin::Utils.save!(row, row.unwrap!, row.class.llm_plugin_options) } }

  include_examples "a persisted context record"

  let(:wrap) { ->(klass) { klass.plugin :llm; klass } }

  include_examples "inherited wrapper callbacks"

  describe "#unwrap!" do
    it "returns the record's LLM::Context" do
      expect(record.unwrap!).to be_a(LLM::Context)
    end

    it "returns the same object on every call" do
      expect(record.unwrap!).to be(record.unwrap!)
    end

    it "returns the runtime the record's own methods use" do
      expect(record.unwrap!.messages).to be(record.messages!)
    end
  end

  describe "#compactor and #compactor_options" do
    it "returns the Null compactor and empty options by default" do
      expect(record.compactor).to be(LLM::Compactor::Null)
      expect(record.compactor_options).to eq({})
    end

    context "when set_context gives a compactor and its options" do
      let(:context) do
        stub_const("SpecSequelCompactor", Class.new(LLM::Compactor::Null))
        Class.new(model) do
          plugin :llm

          private

          def set_provider
            LLM.openai(key: "secret")
          end

          def set_context
            {compactor: SpecSequelCompactor, compactor_options: {threshold: 5}}
          end
        end
      end

      it "returns them from the runtime" do
        expect(record.compactor).to be(SpecSequelCompactor)
        expect(record.compactor_options).to eq({threshold: 5})
        record.compactor_options[:threshold] = 1
        expect(record.compactor_options).to eq({threshold: 5})
      end
    end
  end

  describe "#intercept and #intercept_options" do
    it "returns a Null intercept and empty options by default" do
      expect(record.intercept).to be_a(LLM::Intercept::Null)
      expect(record.intercept_options).to eq({})
    end

    context "when set_context gives an intercept and its options" do
      let(:context) do
        stub_const("SpecSequelIntercept", Class.new(LLM::Intercept::Null))
        Class.new(model) do
          plugin :llm

          private

          def set_provider
            LLM.openai(key: "secret")
          end

          def set_context
            {intercept: SpecSequelIntercept, intercept_options: {threshold: 5}}
          end
        end
      end

      it "returns them from the runtime" do
        expect(record.intercept).to be_a(SpecSequelIntercept)
        expect(record.intercept.options).to eq({threshold: 5})
        expect(record.intercept_options).to eq({threshold: 5})
        record.intercept_options[:threshold] = 1
        expect(record.intercept_options).to eq({threshold: 5})
      end
    end
  end

  context "with a live OpenAI completion",
          vcr: {cassette_name: "openai/chat/completion_contract"} do
    let(:context) do
      Class.new(model) do
        plugin(:llm, tracer: -> { LLM::Tracer.logger(llm, io: StringIO.new) })

        private

        def set_provider
          LLM.openai(key: "secret")
        end

        def set_context
          {model: "gpt-4.1"}
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
