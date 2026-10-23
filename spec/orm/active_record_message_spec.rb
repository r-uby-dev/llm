# frozen_string_literal: true

require "setup"
require "active_record"
require "pg"
require "llm/active_record"

RSpec.describe LLM::ActiveRecord::Message do
  before do
    reason = LLM::Test::Harness.postgres_unavailable_reason
    skip reason if reason
    ActiveRecord::Base.establish_connection(LLM::Test::Harness.postgres_url)
  end

  let(:model) do
    LLM::Test::Harness.build_active_record_model(
      :spec_active_record_message_views, adapter: :postgres, jsonb: true
    ) do
      self.table_name = "spec_active_record_message_views"
      acts_as_llm(format: :jsonb)
    end
  end

  let(:provider_model) do
    LLM::Test::Harness.build_active_record_model(
      :spec_active_record_message_providers, adapter: :postgres, jsonb: true
    ) do
      self.table_name = "spec_active_record_message_providers"
      acts_as_llm(format: :jsonb)

      private

      def set_provider
        LLM.openai(key: "secret")
      end
    end
  end

  let(:agent) { model.create!(data: saved(messages)) }
  let(:provider_record) { provider_model.create!(data: saved(messages)) }
  let(:other_agent) { model.create!(data: saved(other_messages)) }
  let(:assistant_id) { messages.last[:id] }
  let(:relation) { described_class.for(agent:) }

  let(:messages) do
    [
      {id: SecureRandom.uuid_v7, role: "user", content: "hello"},
      {
        id: SecureRandom.uuid_v7,
        role: "assistant",
        content: "hi",
        reasoning_content: "thinking",
        usage: {"total_tokens" => 42},
        tools: [{id: "call_1", name: "echo", arguments: {"value" => "x"}}]
      }
    ]
  end

  let(:other_messages) do
    [{id: SecureRandom.uuid_v7, role: "user", content: "other"}]
  end

  def saved(messages)
    {schema_version: LLM::Context.schema_version, messages:}
  end

  describe ".for" do
    it "returns a relation" do
      expect(relation).to be_a(ActiveRecord::Relation)
    end

    it "returns one row per message" do
      expect(relation.count).to eq(2)
    end

    it "scopes the relation to the agent" do
      expect(described_class.for(agent: other_agent).pluck(:content)).to eq(["other"])
    end

    it "numbers the messages by position" do
      expect(relation.order(:position).pluck(:position)).to eq([1, 2])
    end

    it "exposes the role as a column" do
      expect(relation.order(:position).pluck(:role)).to eq(%w[user assistant])
    end

    it "exposes the content as a column" do
      expect(relation.order(:position).pluck(:content)).to eq(%w[hello hi])
    end

    it "exposes the tool calls as a column" do
      expect(relation.order(:position).last.tools).to eq(
        [{"id" => "call_1", "name" => "echo", "arguments" => {"value" => "x"}}]
      )
    end

    it "chains a where clause" do
      expect(relation.where(role: "assistant").count).to eq(1)
    end
  end

  describe "#messages" do
    it "reads the messages without building a runtime" do
      expect(agent.messages.count).to eq(2)
    end

    it "returns a relation" do
      expect(agent.messages).to be_a(ActiveRecord::Relation)
    end

    it "keeps the conversation order" do
      expect(agent.messages.order(:position).pluck(:role)).to eq(%w[user assistant])
    end

    it "hands back rows the runtime can unwrap" do
      expect(agent.messages.order(:position).first.unwrap!).to be_a(LLM::Message)
    end
  end

  describe "#messages!" do
    it "reads the messages from the runtime" do
      expect(provider_record.messages!).to be_a(LLM::Buffer)
    end

    it "reads them even though #messages answers with the view" do
      expect(provider_record.messages).to be_a(ActiveRecord::Relation)
    end
  end

  describe "fields" do
    let(:row) { relation.order(:position).last }
    let(:first_row) { relation.order(:position).first }
    let(:tools) do
      [{"id" => "call_1", "name" => "echo", "arguments" => {"value" => "x"}}]
    end

    it "exposes #agent_id" do
      expect(row.agent_id).to eq(agent.id)
    end

    it "exposes #id" do
      expect(row.id).to eq(assistant_id)
    end

    it "exposes #role" do
      expect(row.role).to eq("assistant")
    end

    it "exposes #content" do
      expect(row.content).to eq("hi")
    end

    it "exposes #tools" do
      expect(row.tools).to eq(tools)
    end

    it "exposes #tools as nil when a message has none" do
      expect(first_row.tools).to be_nil
    end

    it "exposes #position" do
      expect(row.position).to eq(2)
    end

    it "exposes #data" do
      expect(row.data).to include("role" => "assistant", "content" => "hi")
    end

    it "tracks the fields as attributes" do
      expect(row.attribute_names).to include(
        "agent_id", "id", "role", "content", "tools", "position", "data"
      )
    end

    it "exposes #role on the first message" do
      expect(first_row.role).to eq("user")
    end

    it "exposes #content on the first message" do
      expect(first_row.content).to eq("hello")
    end
  end

  describe "#unwrap!" do
    let(:row) { relation.order(:position).last }

    it "returns a runtime message" do
      expect(row.unwrap!).to be_a(LLM::Message)
    end

    it "keeps the stored id" do
      expect(row.unwrap!.id).to eq(assistant_id)
    end

    it "keeps the content" do
      expect(row.unwrap!.content).to eq("hi")
    end

    it "keeps the reasoning content" do
      expect(row.unwrap!.reasoning_content).to eq("thinking")
    end

    it "keeps the usage" do
      expect(row.unwrap!.token_usage.total_tokens).to eq(42)
    end

    it "keeps the tool calls" do
      expect(row.unwrap!.extra.tool_calls).to eq(
        [{"id" => "call_1", "name" => "echo", "arguments" => {"value" => "x"}}]
      )
    end

    it "derives the creation time from the id" do
      expect(row.unwrap!.created_at).to be_within(5).of(Time.now.utc)
    end
  end

  describe "#tool_call?" do
    it "returns true when the message carries tool calls" do
      expect(relation.order(:position).last.tool_call?).to be(true)
    end

    it "returns false when the message carries no tool calls" do
      expect(relation.order(:position).first.tool_call?).to be(false)
    end
  end

  describe "#tool_return?" do
    it "returns false when the message carries no tool returns" do
      expect(relation.order(:position).last.tool_return?).to be(false)
    end
  end
end
