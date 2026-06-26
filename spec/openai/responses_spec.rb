# frozen_string_literal: true

require "setup"

RSpec.describe "LLM::OpenAI::Responses" do
  let(:key) { ENV["OPENAI_SECRET"] || "TOKEN" }
  let(:provider) { LLM.openai(key:) }

  context "when given a successful create operation",
          vcr: {cassette_name: "openai/responses/successful_create"} do
    subject { provider.responses.create("Hello", role: :developer) }

    it "is successful" do
      is_expected.to be_instance_of(LLM::Response)
    end

    it "has outputs" do
      is_expected.to have_attributes(
        choices: [instance_of(LLM::Message)]
      )
    end
  end

  context "when given a successful get operation",
          vcr: {cassette_name: "openai/responses/successful_get"} do
    let(:response) { provider.responses.create("Hello", role: :developer) }
    subject { provider.responses.get(response) }

    it "is successful" do
      is_expected.to be_instance_of(LLM::Response)
    end

    it "has outputs" do
      is_expected.to have_attributes(
        choices: [instance_of(LLM::Message)]
      )
    end
  end

  context "when given a successful delete operation",
          vcr: {cassette_name: "openai/responses/successful_delete"} do
    let(:response) { provider.responses.create("Hello", role: :developer) }
    subject { provider.responses.delete(response) }

    it "is successful" do
      is_expected.to have_attributes(
        deleted: true
      )
    end
  end

  context "when given a json schema",
          vcr: {cassette_name: "openai/responses/json_schema"} do
    subject do
      schema = provider.schema.object(answer: provider.schema.string.required)
      provider.responses.create("What is the capital of France?", role: :user, schema:)
    end

    it "is successful" do
      is_expected.to be_instance_of(LLM::Response)
    end

    it "has outputs" do
      is_expected.to have_attributes(
        choices: [have_attributes(content: /Paris/)]
      )
    end

    it "has token usage" do
      is_expected.to have_attributes(
        prompt_tokens: be_a(Integer),
        completion_tokens: be_a(Integer),
        total_tokens: be_a(Integer)
      )
    end
  end

  context "when given a function call",
          vcr: {cassette_name: "openai/responses/function_call"} do
    let(:ctx) { LLM::Context.new(provider, mode: :responses, tools: [tool]) }
    let(:tool) do
      LLM.function(:system) do |fn|
        fn.description "Runs system commands"
        fn.params { _1.object(command: _1.string.description("The command to run").required) }
        fn.define { |command:| {success: Kernel.system(command)} }
      end
    end
    let(:prompt) do
      ctx.build_prompt do
        _1.system "You are a bot that can run UNIX commands"
        _1.user "What is the date?"
      end
    end

    before do
      allow(Kernel).to receive(:system).and_return("2024-01-01")
    end

    it "calls a function" do
      ctx.talk(prompt)
      expect(ctx.functions).not_to be_empty
      ctx.talk ctx.wait(:call)
      expect(ctx.functions).to be_empty
    end
  end

  context "when given text streaming",
          vcr: {cassette_name: "openai/responses/text_streaming"} do
    let(:stream) { StringIO.new }

    subject do
      provider.responses.create(
        "Explain the theory of relativity in simple terms.",
        role: :user,
        stream:
      )
    end

    it "is successful" do
      is_expected.to be_instance_of(LLM::Response)
    end

    it "has outputs" do
      is_expected.to have_attributes(
        choices: [have_attributes(content: include("relativity"))]
      )
    end

    it "streams text" do
      is_expected
      expect(stream.string).to include("relativity")
    end
  end

  context "when given a context and an IO stream for responses",
          vcr: {cassette_name: "openai/responses/bot_text_stream"} do
    let(:params) { {stream:} }
    let(:stream) { StringIO.new }
    let(:ctx) { LLM::Context.new(provider, params.merge(mode: :responses)) }
    let(:system_prompt) do
      "Keep your answers short and concise, and provide three answers to the three questions. " \
      "There should be one answer per line. " \
      "An answer should be a number, for example: 5. " \
      "Nothing else"
    end
    let(:prompt) do
      ctx.build_prompt do
        _1.user system_prompt
        _1.user "What is 3+2 ?"
        _1.user "What is 5+5 ?"
        _1.user "What is 5+7 ?"
      end
    end

    before { ctx.talk(prompt) }

    context "with the contents of the IO" do
      subject { stream.string }
      it { is_expected.to match(%r_5\s*\n10\s*\n12\s*_) }
    end

    context "with the contents of the message" do
      subject { ctx.messages.find(&:assistant?) }
      it { is_expected.to have_attributes(role: %r_(assistant|model)_, content: %r_5\s*\n10\s*\n12\s*_) }
    end
  end

  context "when given a context and a tool stream for responses",
          vcr: {cassette_name: "openai/responses/bot_tool_stream"} do
    let(:params) { {stream: true, tools: [tool]} }
    let(:ctx) { LLM::Context.new(provider, params.merge(mode: :responses)) }
    let(:tool) do
      LLM.function(:system) do |fn|
        fn.description "Runs system commands"
        fn.params { _1.object(command: _1.string.required) }
        fn.define { |command:| {success: Kernel.system(command)} }
      end
    end
    let(:prompt) do
      ctx.build_prompt do
        _1.system "You are a bot that can run UNIX commands"
        _1.user "What is the date?"
      end
    end

    before { ctx.talk(prompt) }

    it "calls the function(s)" do
      expect(Kernel).to receive(:system).with(/date/).and_return("2024-01-01")
      ctx.talk ctx.wait(:call)
      expect(ctx.functions).to be_empty
    end
  end

  context "when given the web search tool",
          vcr: {cassette_name: "openai/responses/remote_tool"} do
    subject(:create_response) do
      provider.responses.create(
        "What was a positive news story from today?",
        params.merge(role: :user)
      )
    end
    let(:params) { {tools: [{type: "web_search"}]} }

    it "performs a web search" do
      res = create_response
      expect(res.annotations).not_to be_empty
    end
  end
end
