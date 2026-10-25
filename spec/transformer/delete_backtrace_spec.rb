# frozen_string_literal: true

require "setup"

RSpec.describe LLM::Transformer::DeleteBacktrace,
               vcr: {cassette_name: "openai/chat/llm_function_class"} do
  let(:llm) { LLM.openai(key: "test") }
  let(:transformer) { described_class }
  let(:tool) do
    Class.new(LLM::Tool) do
      name "system"
      description "Runs a command"
      param :command, String, "A command", required: true

      def call(command:)
        raise "boom: #{command}"
      end
    end
  end
  let(:agent) { LLM::Agent.new(llm, tools: [tool], transformer:) }
  let(:ctx) { agent.instance_variable_get(:@ctx) }
  let(:returns) do
    ctx.messages
      .flat_map { |message| [*message.content].flatten }
      .grep(LLM::Function::Return)
  end
  let(:error) { returns.find(&:error?) }

  before do
    agent.talk("What is the date?")
  end

  it "ran the tool, so there is an error to strip" do
    expect(error.value[:message]).to include("boom")
  end

  it "strips the backtrace from the tool's error" do
    expect(error.value).not_to have_key(:backtrace)
  end

  it "keeps the error" do
    expect(error.value[:error]).to be(true)
  end

  context "with the no-op transformer" do
    let(:transformer) { LLM::Transformer::Null }

    it "strips the backtrace anyway" do
      expect(error.value).not_to have_key(:backtrace)
    end
  end
end
