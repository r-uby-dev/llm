# frozen_string_literal: true

require "setup"
require "active_record"
require "sqlite3"
require "stringio"
require "llm/active_record"

RSpec.describe "acts_as_agent" do
  let(:model) { LLM::Test::Harness.build_active_record_model(:spec_active_record_agents) }
  let(:tool) do
    Class.new(LLM::Tool) do
      name "echo"
      description "Echo a value"
    end
  end
  let(:schema) do
    Class.new(LLM::Schema) do
      property :answer, String, "Answer", required: true
    end
  end
  let(:skill_path) { "/tmp/weather" }

  let(:agent) do
    Class.new(model) do
      acts_as_agent(tracer: -> { LLM::Tracer.logger(llm, io: StringIO.new) }) do |agent|
        agent.description :described_by_the_model
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

      def described_by_the_model
        "described by the model"
      end
    end
  end

  let(:record) { agent.create! }
  let(:reload_record) { ->(row) { row.class.find(row.id) } }
  let(:flush_record) { ->(row) { LLM::ActiveRecord::Utils.save!(row, row.send(:ctx), row.class.llm_plugin_options) } }

  it "forwards confirm to the internal agent class" do
    expect(agent.agent.confirm).to eq(["delete-file"])
  end

  describe "the internal agent class name" do
    let(:model_class) do
      stub_const("SpecAgentModel", Class.new(model))
    end

    before do
      model_class.acts_as_agent do |agent|
        agent.model "gpt-5.4-mini"
      end
    end

    it "derives the name from the model class" do
      expect(model_class.agent.name).to eq("spec-agent-model")
    end
  end

  context "when tools are declared with a block" do
    let(:agent) do
      tool
      Class.new(model) do
        acts_as_agent do |agent|
          agent.tools { tools }
        end

        private

        def set_provider
          LLM.openai(key: "secret")
        end

        def tools
          [LLM::Tool.registry.first]
        end
      end
    end

    it "forwards the block to the internal agent class" do
      expect(agent.agent.tools).to be_a(Proc)
    end
  end

  context "when tools are declared via a symbol on the record" do
    let(:agent) do
      tool = self.tool
      Class.new(model) do
        acts_as_agent do |agent|
          agent.tools :tools
        end

        private

        define_method(:tools) do
          [tool]
        end

        def set_provider
          LLM.openai(key: "secret")
        end
      end
    end

    it "resolves the tools against the bound record" do
      expect(record.send(:ctx).params[:tools]).to eq([tool])
    end
  end

  context "when model is declared with a block" do
    let(:agent) do
      Class.new(model) do
        acts_as_agent do |agent|
          agent.model { "gpt-4.1" }
        end

        private

        def set_provider
          LLM.openai(key: "secret")
        end
      end
    end

    it "forwards the block to the internal agent class" do
      expect(agent.agent.model).to be_a(Proc)
    end
  end

  context "when skills are declared with a block" do
    let(:agent) do
      skill_path = self.skill_path
      Class.new(model) do
        acts_as_agent do |agent|
          agent.skills { [skill_path] }
        end

        private

        def set_provider
          LLM.openai(key: "secret")
        end
      end
    end

    it "forwards the block to the internal agent class" do
      expect(agent.agent.skills).to be_a(Proc)
    end
  end

  context "when schema is declared with a block" do
    let(:agent) do
      schema = self.schema
      Class.new(model) do
        acts_as_agent do |agent|
          agent.schema { schema }
        end

        private

        def set_provider
          LLM.openai(key: "secret")
        end
      end
    end

    it "forwards the block to the internal agent class" do
      expect(agent.agent.schema).to be_a(Proc)
    end
  end

  context "when the tracer is declared in the block" do
    let(:agent) do
      Class.new(model) do
        acts_as_agent do |agent|
          agent.model "gpt-5.4-mini"
          agent.tracer -> { LLM::Tracer.logger(llm, io: StringIO.new) }
        end

        private

        def set_provider
          LLM.openai(key: "secret")
        end
      end
    end

    it "resolves the tracer from the block" do
      expect(record.send(:ctx).tracer).to be_a(LLM::Tracer::Logger)
    end
  end

  include_examples "a persisted agent record"

  let(:wrap) { ->(klass) { klass.acts_as_agent; klass } }

  include_examples "inherited wrapper callbacks"

  context "with a live OpenAI completion",
          vcr: {cassette_name: "openai/chat/completion_contract"} do
    let(:agent) do
      Class.new(model) do
        acts_as_agent(tracer: -> { LLM::Tracer.logger(llm, io: StringIO.new) }) do |agent|
          agent.model "gpt-4.1"
        end

        private

        def set_provider
          LLM.openai(key: "secret")
        end
      end
    end

    let(:record) { agent.create! }

    it "persists the returned messages" do
      result = record.talk("Hello, world!")
      expect(result).to be_a(LLM::Response)
      expect(reload_record.call(record).messages.last).to be_a(LLM::Message)
      expect(reload_record.call(record).messages.last.content).not_to be_empty
    end
  end

  context "with jsonb serialization" do
    let(:original_tool_calls) do
      LLM::Object.from([
        {
          "index" => 0,
          "id" => "call_00_x",
          "type" => "function",
          "function" => {
            "name" => "echo",
            "arguments" => "{\"value\": \"hi\"}"
          }
        }
      ])
    end
    let(:tool_calls) { [{id: "call_00_x", name: "echo", arguments: {"value" => "hi"}}] }
    let(:ctx) { LLM::Context.new(LLM.openai(key: "secret")) }
    let(:data) { LLM::ActiveRecord::Utils.serialize_context(ctx, :jsonb) }
    let(:message) do
      ##
      # ActiveRecord encodes jsonb columns with
      # ActiveSupport::JSON.encode, which must not
      # see LLM::Object values becuz it would encode
      # them as arrays of [key, value] pairs instead
      # of JSON objects.
      JSON.parse(ActiveSupport::JSON.encode(data)).fetch("messages").fetch(0)
    end

    before do
      ctx.messages << LLM::Message.new(
        "assistant",
        nil,
        tool_calls:,
        original_tool_calls:
      )
    end

    it "stores original_tool_calls as an object" do
      expect(message.dig("original_tool_calls", 0)).to be_a(Hash)
    end

    it "stores the tool call function as an object" do
      expect(message.dig("original_tool_calls", 0, "function")).to be_a(Hash)
    end

    it "stores tool call arguments as an object" do
      expect(message.dig("tools", 0, "arguments")).to be_a(Hash)
    end
  end
end
