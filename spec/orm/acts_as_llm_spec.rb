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
      acts_as_llm(tracer: -> { LLM::Tracer.logger(llm, io: StringIO.new) })

      private

      def set_provider
        LLM.openai(key: "secret")
      end

      def set_context
        {model: "gpt-5.4-mini", mode: :responses, store: false}
      end
    end
  end

  let(:record) { context.create! }
  let(:reload_record) { ->(row) { row.class.find(row.id) } }
  let(:flush_record) { ->(row) { LLM::ActiveRecord::Utils.save!(row, row.send(:ctx), row.class.llm_plugin_options) } }

  include_examples "a persisted context record"

  let(:wrap) { ->(klass) { klass.acts_as_llm; klass } }

  include_examples "inherited wrapper callbacks"

  describe "#messages" do
    it "reads the messages from the runtime" do
      expect(record.messages).to be_a(LLM::Buffer)
    end

    context "when the format is json rather than jsonb" do
      let(:context) do
        Class.new(model) do
          acts_as_llm(format: :json)

          private

          def set_provider
            LLM.openai(key: "secret")
          end
        end
      end

      it "still reads them from the runtime" do
        expect(record.messages).to be_a(LLM::Buffer)
      end
    end
  end

  context "with a live OpenAI completion",
          vcr: {cassette_name: "openai/chat/completion_contract"} do
    let(:context) do
      Class.new(model) do
        acts_as_llm(tracer: -> { LLM::Tracer.logger(llm, io: StringIO.new) })

        private

        def set_provider
          LLM.openai(key: "secret")
        end

        def set_context
          {model: "gpt-4.1"}
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
