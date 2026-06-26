# frozen_string_literal: true

require_relative "setup"
require "tmpdir"

RSpec.describe LLM::Skill do
  class WeatherTool < LLM::Tool
    name "weather"
    description "Get the current weather"

    def call(**)
      {content: "sunny"}
    end
  end

  class EchoTool < LLM::Tool
    name "echo"
    description "Echos a greeting"

    def call
      {echo: "Hello world"}
    end
  end

  around do |example|
    Dir.mktmpdir do |dir|
      @dir = dir
      example.run
    end
  end

  before do
    LLM::Tool.clear_registry!
    LLM::Tool.register(WeatherTool)
    LLM::Tool.register(EchoTool)
  end

  let(:skill_dir) { File.join(@dir, "weather") }
  let(:provider) { LLM.openai(key: "test") }
  let(:responses) { provider.responses }
  let(:stream) { LLM::Stream.new }
  let(:ctx) { LLM::Context.new(provider, tools: [EchoTool], model: "gpt-5.4-mini", stream:) }

  describe ".load" do
    subject(:skill) { described_class.load(skill_dir) }

    context "when given a skill without tools" do
      before do
        write("SKILL.md", <<~MD)
          ---
          name: weather
          description: Get the current weather
          ---
          Use the helper tools to answer the user's question.
        MD
      end

      it "loads metadata from SKILL.md" do
        expect(skill.name).to eq("weather")
        expect(skill.description).to eq("Get the current weather")
        expect(skill.frontmatter.name).to eq("weather")
        expect(skill.frontmatter.description).to eq("Get the current weather")
      end

      it "exposes the instructions body" do
        expect(skill.instructions).to include("Use the helper tools")
      end
    end

    context "when given a skill with tools" do
      before do
        write("SKILL.md", <<~MD)
          ---
          name: weather
          description: Get the current weather
          tools: ['weather']
          ---
          Use the helper tools to answer the user's question.
        MD
      end

      it "loads tools from SKILL.md" do
        expect(skill.tools).to eq([WeatherTool])
      end

      it "raises when a tool is missing" do
        write("SKILL.md", <<~MD)
          ---
          tools: ['missing']
          ---
          Use the helper tools to answer the user's question.
        MD
        expect { described_class.load(skill_dir) }.to raise_error(LLM::NoSuchToolError, /missing/)
      end
    end

    context "when given a skill that inherits tools" do
      before do
        write("SKILL.md", <<~MD)
          ---
          name: weather
          description: Get the current weather
          tools: inherit
          ---
          Use the available tools
        MD
      end
      let(:agent) { skill.method(:agent).call(ctx) }

      it "inherits tools" do
        expect(skill.inherit_tools?).to be(true)
      end

      it "includes inherited tools" do
        expect(agent.params[:tools]).to eq([EchoTool])
      end

      context "when the parent context has a skill-backed tool" do
        let(:parent) do
          LLM::Context.new(provider, tools: [EchoTool], skills: [skill_dir], model: "gpt-5.4-mini", stream:)
        end
        let(:agent) { skill.method(:agent).call(parent) }

        it "loads a skill-backed tool through the parent context" do
          expect(parent.params[:tools].any?(&:skill?)).to be(true)
        end

        it "does not inherit skill-backed tools" do
          expect(agent.params[:tools]).to eq([EchoTool])
        end
      end
    end
  end

  describe "#to_tool" do
    let(:skill) { described_class.load(skill_dir) }
    let(:tool) { skill.to_tool(ctx) }

    context "when given a skill with tools" do
      before do
        write("SKILL.md", <<~MD)
          ---
          name: weather
          description: Get the current weather
          tools: ['weather']
          ---
          Use the helper tools.
        MD
      end

      it "builds a tool with the skill metadata" do
        expect(tool.name).to eq("weather")
        expect(tool.description).to eq("Get the current weather")
      end

      it "binds tool execution back to the skill" do
        expect(skill).to receive(:call).with(ctx).and_return({content: "rain"})
        expect(tool.new.call).to eq({content: "rain"})
      end

      it "disables ractor concurrency" do
        function = tool.function.dup.tap do |fn|
          fn.id = "call_1"
          fn.arguments = {}
        end
        expect { function.spawn(:ractor) }.to raise_error(
          LLM::RactorError,
          "Ractor concurrency does not support skill-backed tools"
        )
      end

      it "passes the function tracer back to the skill" do
        provider = LLM.openai(key: "test")
        ctx = LLM::Context.new(provider, model: "gpt-5.4-mini", stream:)
        tracer = double("tracer", llm: provider, on_tool_start: nil, on_tool_finish: nil, on_tool_error: nil)
        tool = skill.to_tool(ctx)
        function = tool.function.dup.tap do |fn|
          fn.id = "call_1"
          fn.arguments = {}
          fn.tracer = tracer
        end
        expect(skill).to receive(:call).with(ctx) do
          expect(ctx.llm.tracer).to equal(tracer)
          {content: "rain"}
        end
        expect(function.spawn(:thread).value.to_h).to eq(
          id: "call_1", name: "weather", value: {content: "rain"}
        )
      end
    end

    context "when given a skill that inherits tools" do
      before do
        write("SKILL.md", <<~MD)
          ---
          name: weather
          description: Get the current weather
          tools: inherit
          ---
          Use the helper tools.
        MD
      end
    end
  end

  describe "#call" do
    before do
      write("SKILL.md", <<~MD)
        ---
        name: weather
        description: Get the current weather
        ---
        Use the helper tools.
      MD
    end

    subject(:call_skill) { skill.call(ctx) }

    let(:skill) { described_class.load(skill_dir) }
    let(:assistant_message) { LLM::Message.new("assistant", "It is raining") }
    let(:res) { double("response", content: "It is raining", choices: [assistant_message]) }

    context "when calling the skill" do
      it "uses an internal agent and returns tool-shaped output" do
        allow(provider).to receive(:responses).and_return(responses)
        expect(responses).to receive(:create) do |prompt, params|
          expect(prompt.to_a.any? { _1.content == "Solve the user's query." }).to eq(true)
          expect(params).to include(model: "gpt-5.4-mini")
          res
        end
        expect(call_skill).to eq({content: "It is raining"})
      end
    end

    context "when the active stream carries concurrency" do
      let(:threads) { Queue.new }
      let(:tool) do
        threads = self.threads
        Class.new(LLM::Tool) do
          name "thread-weather"
          description "Get the current weather"

          define_method(:call) do |**|
            threads << Thread.current
            {content: "sunny"}
          end
        end
      end
      let(:stream) { LLM::Stream.new.tap { _1.extra[:concurrency] = :thread } }
      let(:ctx) { LLM::Context.new(provider, model: "gpt-5.4-mini", stream:) }
      let(:call) do
        LLM::Message.new("assistant", nil, {
          tools: [tool],
          tool_calls: [{id: "call_1", name: "thread-weather", arguments: {}}]
        })
      end
      let(:final_message) { LLM::Message.new("assistant", "It is raining") }
      let(:first_response) { double("response", choices: [call], content: nil) }
      let(:res) { double("response", choices: [final_message], content: "It is raining") }

      before do
        write("SKILL.md", <<~MD)
          ---
          name: weather
          description: Get the current weather
          tools:
            - thread-weather
          ---
          Use the helper tools.
        MD
      end

      it "inherits the concurrency" do
        allow(provider).to receive(:responses).and_return(responses)
        expect(responses).to receive(:create).ordered.and_return(first_response, res)
        expect(call_skill).to eq({content: "It is raining"})
        expect(threads.pop).not_to eq(Thread.current)
      end
    end

    context "when the parent context has a schema" do
      let(:ctx) { LLM::Context.new(provider, model: "gpt-5.4-mini", schema: :schema, stream:) }

      it "does not pass the schema into the nested agent request" do
        allow(provider).to receive(:responses).and_return(responses)
        expect(responses).to receive(:create) do |prompt, params|
          expect(prompt.to_a.any? { _1.content == "Solve the user's query." }).to eq(true)
          expect(params).not_to have_key(:schema)
          res
        end
        call_skill
      end
    end

    context "when the parent context has recent user and assistant messages" do
      before do
        ctx.messages << LLM::Message.new(:system, "Ignore this")
        ctx.messages << LLM::Message.new(:user, "What is today's date?")
        ctx.messages << LLM::Message.new(:assistant, "Let me check.")
        ctx.messages << LLM::Message.new(:assistant, nil, tool_calls: [{id: "x", name: "weather", arguments: "{}"}])
        ctx.messages << LLM::Message.new(:tool, LLM::Function::Return.new("x", "weather", {content: "sunny"}))
      end

      it "inherits a curated slice of parent messages" do
        allow(provider).to receive(:responses).and_return(responses)
        expect(responses).to receive(:create) do |prompt, params|
          expect(prompt.to_a.any? { _1.content == "Solve the user's query." }).to eq(true)
          expect(params[:input].map(&:content)).to eq(["Recent context:", "What is today's date?", "Let me check."])
          res
        end
        call_skill
      end
    end
  end

  def write(path, content)
    full = File.join(skill_dir, path)
    FileUtils.mkdir_p(File.dirname(full))
    File.write(full, content)
  end
end
