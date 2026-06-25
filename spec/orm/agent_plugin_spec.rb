# frozen_string_literal: true

require "setup"
require "sequel"
require "sqlite3"
require "stringio"
require "sequel/plugins/agent"

RSpec.describe "plugin :agent" do
  let(:model) { LLM::Test::Harness.build_sequel_model(:spec_sequel_agents) }
  let(:tool) do
    Class.new(LLM::Tool) do
      name "echo"
      description "Echo a value"
    end
  end

  let(:agent) do
    Class.new(model) do
      plugin :agent, tracer: :set_tracer do |agent|
        agent.model "gpt-5.4-mini"
        agent.instructions "You are concise."
        agent.concurrency :thread
        agent.confirm "delete-file"
      end

      private

      def set_provider
        LLM.openai(key: "secret")
      end

      def set_context
        {mode: :responses, store: false}
      end

      def set_tracer
        LLM::Tracer::Logger.new(llm, io: StringIO.new)
      end
    end
  end

  let(:record) { agent.create }
  let(:reload_record) { ->(row) { row.class[row.id] } }
  let(:flush_record) { ->(row) { LLM::Sequel::Plugin::Utils.save!(row, row.send(:ctx), row.class.llm_plugin_options) } }

  it "forwards confirm to the internal agent class" do
    expect(agent.agent.confirm).to eq(["delete-file"])
  end

  context "when tools are declared with a block" do
    let(:agent) do
      tool = self.tool
      Class.new(model) do
        plugin :agent do |agent|
          agent.tools { [tool] }
        end

        private

        def set_provider
          LLM.openai(key: "secret")
        end
      end
    end

    it "forwards the block to the internal agent class" do
      expect(agent.agent.tools).to be_a(Proc)
    end
  end

  include_examples "a persisted agent record"

  context "with a live OpenAI completion",
          vcr: {cassette_name: "openai/chat/completion_contract"} do
    let(:agent) do
      Class.new(model) do
        plugin :agent, tracer: :set_tracer do |agent|
          agent.model "gpt-4.1"
        end

        private

        def set_provider
          LLM.openai(key: "secret")
        end

        def set_tracer
          LLM::Tracer::Logger.new(llm, io: StringIO.new)
        end
      end
    end

    let(:record) { agent.create }

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
          :spec_sequel_agents_jsonb,
          adapter: :postgres,
          jsonb: true
        )
      end
      let(:agent) do
        Class.new(model) do
          plugin :agent, format: :jsonb do |agent|
            agent.model "gpt-4.1"
          end

          private

          def set_provider
            LLM.openai(key: "secret")
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
