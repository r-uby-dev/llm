# frozen_string_literal: true

require_relative "setup"
require "fileutils"
require "tmpdir"

RSpec.describe LLM::Agent do
  let(:provider) { LLM.openai(key: "test") }
  let(:empty_functions) { [].extend(LLM::Function::Array) }
  let(:tool) do
    Class.new(LLM::Tool) do
      name "echo"
      description "Echo a value"
      param :value, String, "Value", required: true
      def call(value:) = {value:}
    end
  end

  describe "tracing" do
    let(:responses) { provider.responses }
    let(:final_response) { response!(choices: [LLM::Message.new("assistant", "done")]) }
    let(:trace_events) { [] }
    let(:tracer) do
      events = trace_events
      LLM::Tracer.new(provider).tap do |tracer|
        tracer.define_singleton_method(:on_exit) { nil }
        tracer.define_singleton_method(:start_trace) { |**opts| events << [:start, opts]; self }
        tracer.define_singleton_method(:stop_trace) { events << [:stop]; self }
      end
    end
    let(:agent) { described_class.new(provider, mode: :responses, tracer:) }

    before do
      allow(provider).to receive(:responses).and_return(responses)
      expect(responses).to receive(:create).and_return(final_response)
    end

    context "when the agent has a tracer" do
      before { agent.talk("hello") }

      it "brackets the turn in a trace group" do
        expect(trace_events.map(&:first)).to eq([:start, :stop])
      end

      it "names the group after the turn" do
        expect(trace_events.first.last[:name]).to eq("llm.turn")
      end

      it "gives the group an id" do
        expect(trace_events.first.last[:trace_group_id]).to match(/\A\h{8}-/)
      end
    end

    context "when only the provider has a tracer" do
      let(:agent) { described_class.new(provider, mode: :responses) }

      before do
        provider.tracer = tracer
        agent.talk("hello")
      end

      it "brackets the turn in a trace group" do
        expect(trace_events.map(&:first)).to eq([:start, :stop])
      end
    end
  end

  describe ".tools" do
    context "when resolved via a symbol" do
      let(:agent) do
        _tool = tool
        Class.new(described_class) do
          tools :set_tools
          define_method(:set_tools) { _tool }
        end.new(provider)
      end

      it "resolves successfully" do
        expect(agent.params[:tools]).to eq([tool])
      end
    end

    context "when resolved via a proc" do
      let(:agent) do
        _tool = tool
        Class.new(described_class) do
          tools proc { [_tool] }
        end.new(provider)
      end

      it "resolves the proc to the tool list" do
        expect(agent.params[:tools]).to eq([tool])
      end
    end

    context "when given a single proc via set" do
      let(:agent) do
        _tool = tool
        Class.new(described_class) do
          set tools: proc { [_tool] }
        end.new(provider)
      end

      it "resolves the proc to the tool list" do
        expect(agent.params[:tools]).to eq([tool])
      end
    end

    context "when resolved via a symbol through set" do
      let(:agent) do
        _tool = tool
        Class.new(described_class) do
          set tools: :set_tools
          define_method(:set_tools) { _tool }
        end.new(provider)
      end

      it "resolves successfully" do
        expect(agent.params[:tools]).to eq([tool])
      end
    end

    context "when resolved via the :tools method through set" do
      let(:agent) do
        _tool = tool
        Class.new(described_class) do
          set tools: :tools
          define_method(:tools) { [_tool] }
        end.new(provider)
      end

      it "resolves successfully" do
        expect(agent.params[:tools]).to eq([tool])
      end
    end
  end

  describe ".name" do
    context "when given an instance of LLM::Agent" do
      let(:agent) { described_class.new(provider) }

      it "derives a name from the class name" do
        expect(agent.name).to eq("agent")
      end
    end

    context "when no name is set on the class" do
      before { stub_const "TestAgent", Class.new(described_class) }
      let(:agent) { TestAgent }
      it "derives a name from the class name" do
        expect(agent.name).to eq("test-agent")
      end
    end

    context "when a custom name is set" do
      let(:agent) do
        Class.new(described_class) do
          name "admin"
        end
      end

      it "returns the custom name" do
        expect(agent.name).to eq("admin")
      end
    end
  end

  describe ".description" do
    context "when no description is set on the class" do
      let(:agent) { Class.new(described_class) }
      it "returns nil" do
        expect(agent.description).to eq(nil)
      end
    end

    context "when a description is set" do
      let(:agent) do
        Class.new(described_class) do
          description "release engineer"
        end
      end

      it "returns the description" do
        expect(agent.description).to eq("release engineer")
      end
    end
  end

  shared_examples "agent behavior" do
    let(:schema) do
      Class.new(LLM::Schema) do
        property :answer, String, "Answer", required: true
      end
    end

    let(:agent_class) do
      tool_class = tool
      schema_class = schema
      Class.new(described_class) do
        model "gpt-4.1"
        instructions "You are helpful"
        tools tool_class
        schema schema_class
      end
    end

    describe ".new" do
      let(:skill_path) do
        dir = Dir.mktmpdir("llmrb-skill")
        File.write(File.join(dir, "SKILL.md"), <<~MD)
          ---
          name: weather
          description: Check the weather
          ---
          You are a weather skill.
        MD
        dir
      end

      after do
        FileUtils.remove_entry(skill_path)
      end

      it "passes DSL defaults to the context" do
        ctx = wrapped_context(agent_class.new(provider))
        expect(ctx.params[:model]).to eq("gpt-4.1")
        expect(ctx.params[:tools]).to eq([tool])
        expect(ctx.params[:schema]).to eq(schema)
      end

      it "keeps concurrency on the agent" do
        klass = Class.new(described_class) do
          model "gpt-4.1"
          concurrency :thread
        end
        expect(klass.new(provider).concurrency).to eq(:thread)
      end

      it "passes the retry budget to the context" do
        klass = Class.new(described_class) do
          retry_budget 5
        end
        expect(wrapped_context(klass.new(provider)).retry_budget).to eq(5)
      end

      context "when no retry budget is set" do
        context "when the provider is openai" do
          let(:agent) { described_class.new(provider) }

          it "defaults to 5 retries" do
            expect(wrapped_context(agent).retry_budget).to eq(5)
          end
        end

        context "when the provider is alibaba" do
          let(:provider) { LLM.alibaba(key: "x") }
          let(:agent) { described_class.new(provider) }

          it "defaults to 8 retries" do
            expect(wrapped_context(agent).retry_budget).to eq(8)
          end

          context "when an explicit retry budget is set" do
            let(:agent) do
              Class.new(described_class) do
                retry_budget 3
              end.new(provider)
            end

            it "keeps the explicit budget" do
              expect(wrapped_context(agent).retry_budget).to eq(3)
            end
          end
        end
      end

      it "passes DSL skills to the context" do
        skill_path = self.skill_path
        klass = Class.new(described_class) do
          model "gpt-4.1"
          skills skill_path
        end
        ctx = wrapped_context(klass.new(provider))
        expect(ctx.params[:tools]).not_to be_empty
      end

      context "when model is declared with a block" do
        let(:klass) do
          Class.new(described_class) do
            model { "gpt-4.1" }
          end
        end

        it "resolves the block against the agent instance" do
          ctx = wrapped_context(klass.new(provider))
          expect(ctx.params[:model]).to eq("gpt-4.1")
        end
      end

      context "when no model is configured" do
        it "keeps the provider default model" do
          ctx = wrapped_context(described_class.new(provider))
          expect(ctx.params[:model]).to eq(provider.default_model)
        end
      end

      context "when a name is declared with a block" do
        let(:klass) do
          Class.new(described_class) do
            name { "block-agent" }
          end
        end
        let(:agent) { klass.new(provider) }

        it "resolves the block against the agent instance" do
          expect(agent.name).to eq("block-agent")
        end
      end

      context "when a description is declared as a symbol" do
        let(:klass) do
          Class.new(described_class) do
            description :described_by_the_agent

            private

            def described_by_the_agent
              "a description from a symbol"
            end
          end
        end
        let(:agent) { klass.new(provider) }

        it "resolves the symbol against the agent instance" do
          expect(agent.description).to eq("a description from a symbol")
        end
      end

      context "when a description is declared with a block" do
        let(:klass) do
          Class.new(described_class) do
            description { "a description from a block" }
          end
        end
        let(:agent) { klass.new(provider) }

        it "resolves the block against the agent instance" do
          expect(agent.description).to eq("a description from a block")
        end
      end

      context "when a path is declared with a block" do
        let(:klass) do
          Class.new(described_class) do
            path { "/tmp/llm.rb-spec-missing-agent" }
          end
        end
        let(:agent) { klass.new(provider) }

        it "resolves the block against the agent instance" do
          expect(agent.path).to eq("/tmp/llm.rb-spec-missing-agent")
        end
      end

      context "when a tool budget is declared with a block" do
        let(:klass) do
          Class.new(described_class) do
            tool_budget { 3 }
          end
        end
        let(:agent) { klass.new(provider) }
        let(:tool_budget) { agent.instance_variable_get(:@tool_budget) }

        it "resolves the block against the agent instance" do
          expect(tool_budget).to eq(3)
        end
      end

      context "when tools are declared with a block" do
        let(:tool) do
          Class.new(LLM::Tool) do
            name "echo"
            description "Echo a value"
          end
        end
        let(:klass) do
          tool_class = tool
          Class.new(described_class) do
            tools { [tool_class] }
          end
        end

        it "resolves the block against the agent instance" do
          ctx = wrapped_context(klass.new(provider))
          expect(ctx.params[:tools]).to eq([tool])
        end
      end

      context "when skills are declared with a block" do
        let(:klass) do
          skill_path = self.skill_path
          Class.new(described_class) do
            skills { [skill_path] }
          end
        end

        it "resolves the block against the agent instance" do
          ctx = wrapped_context(klass.new(provider))
          expect(ctx.params[:tools]).not_to be_empty
        end
      end

      context "when schema is declared with a block" do
        let(:schema) do
          Class.new(LLM::Schema) do
            property :answer, String, "Answer", required: true
          end
        end
        let(:klass) do
          schema_class = schema
          Class.new(described_class) do
            schema { schema_class }
          end
        end

        it "resolves the block against the agent instance" do
          ctx = wrapped_context(klass.new(provider))
          expect(ctx.params[:schema]).to eq(schema)
        end
      end

      context "when configured with a tracer block" do
        let(:tracer) { Object.new }
        let(:agent) do
          tracer = self.tracer
          Class.new(described_class) do
            tracer { tracer }
          end.new(provider)
        end

        it "resolves the tracer without mutating the provider default" do
          expect(agent.tracer).to equal(tracer)
          expect(provider.tracer).to be_a(LLM::Tracer::Null)
        end
      end

      context "when configured with a stream block" do
        let(:stream_class) { Class.new(LLM::Stream) }
        let(:stream) { stream_class.new }
        let(:klass) do
          stream = self.stream
          Class.new(described_class) do
            model "gpt-4.1"
            stream { stream }
          end
        end

        it "resolves the stream before building the context" do
          expect(klass.new(provider).stream).to equal(stream)
        end

        context "when the block builds a new stream" do
          let(:klass) do
            stream_class = self.stream_class
            Class.new(described_class) do
              model "gpt-4.1"
              stream { stream_class.new }
            end
          end
          let(:first_agent) { klass.new(provider) }
          let(:second_agent) { klass.new(provider) }

          it "creates a separate stream per agent instance" do
            expect(first_agent.stream).not_to equal(second_agent.stream)
          end

          it "uses the configured stream type" do
            expect(first_agent.stream).to be_a(stream_class)
            expect(second_agent.stream).to be_a(stream_class)
          end
        end
      end

      context "when configured with a stream object" do
        let(:stream) { Class.new(LLM::Stream).new }
        let(:klass) do
          stream = self.stream
          Class.new(described_class) do
            model "gpt-4.1"
            stream stream
          end
        end

        it "passes the stream to the context" do
          expect(klass.new(provider).stream).to equal(stream)
        end
      end
    end

    describe "#talk" do
      let(:agent) { agent_class.new(provider) }
      let(:responses) { provider.responses }
      let(:prompt) do
        LLM::Prompt.new(provider) do
          system "You are helpful"
          user "hello"
        end
      end
      let(:res) { response!(choices: [LLM::Message.new("assistant", "hello")]) }

      it "sends the prompt through the provider" do
        if provider.name == :openai
          allow(agent.llm).to receive(:responses).and_return(responses)
          expect(responses).to receive(:create)
            .with(array_including(have_attributes(content: "hello")), instance_of(Hash))
            .and_return(res)
        else
          expect(agent.llm).to receive(:complete)
            .with(array_including(have_attributes(content: "hello")), instance_of(Hash))
            .and_return(res)
        end
        agent.talk(prompt)
      end

      context "with preseeded non-system history" do
        let(:existing_messages) { [LLM::Message.new("user", "Earlier task context")] }
        let(:expected_prompt) do
          LLM::Prompt.new(provider) do
            system "You are helpful"
            user "hello"
          end
        end

        before do
          agent.messages.concat(existing_messages)
        end

        it "injects instructions" do
          if provider.name == :openai
            allow(agent.llm).to receive(:responses).and_return(responses)
            expect(responses).to receive(:create)
              .with(array_including(have_attributes(content: "hello"), have_attributes(content: "Earlier task context")), instance_of(Hash))
              .and_return(res)
          else
            expect(agent.llm).to receive(:complete)
              .with(array_including(have_attributes(content: "hello"), have_attributes(content: "Earlier task context")), instance_of(Hash))
              .and_return(res)
          end
          agent.talk("hello")
        end
      end
    end
  end

  describe "context parity" do
    let(:agent) { described_class.new(provider) }
    let(:ctx) { agent.instance_variable_get(:@ctx) }
    let(:tmpdir) { Dir.mktmpdir("llmrb-agent") }
    let(:path) { File.join(tmpdir, "state.json") }

    after { FileUtils.remove_entry(tmpdir) }

    describe "#messages" do
      subject { agent.messages }
      it { is_expected.to be(ctx.messages) }
    end

    describe "#pending_functions" do
      subject { agent.pending_functions }
      it { is_expected.to eq(ctx.pending_functions) }
    end

    describe "#returns" do
      subject { agent.returns }
      it { is_expected.to eq(ctx.returns) }
    end

    describe "#usage" do
      subject { agent.usage }
      it { is_expected.to eq(ctx.usage) }
    end

    describe "#mode" do
      subject { agent.mode }
      it { is_expected.to eq(ctx.mode) }
    end

    describe "#cost" do
      subject { agent.cost }
      it { is_expected.to eq(ctx.cost) }
    end

    describe "#context_window" do
      subject { agent.context_window }
      it { is_expected.to eq(ctx.context_window) }
    end

    describe "#model" do
      subject { agent.model }
      it { is_expected.to eq(ctx.model) }
    end

    describe "#to_h" do
      subject { agent.to_h }
      it { is_expected.to eq(ctx.to_h) }
    end

    describe "#to_json" do
      subject { agent.to_json }
      it { is_expected.to eq(ctx.to_json) }
    end

    describe "#tracer" do
      subject { agent.tracer }
      it { is_expected.to be_a(LLM::Tracer::Null) }
    end

    describe "#params" do
      subject { agent.params }
      it { is_expected.to eq(ctx.params) }
    end

    describe "#prompt" do
      it "forwards to the context" do
        expect(agent.prompt {}).to be_a(LLM::Prompt)
      end
    end

    describe "#image_url" do
      it "forwards to the context" do
        expect(agent.image_url("https://example.com")).to be_a(LLM::Object)
      end
    end

    describe "#local_file" do
      it "forwards to the context" do
        expect(agent.local_file("/tmp/x")).to be_a(LLM::Object)
      end
    end

    describe "#remote_file" do
      it "forwards to the context" do
        expect(agent.remote_file("https://example.com/p.png")).to be_a(LLM::Object)
      end
    end

    describe "#interrupt!" do
      it "forwards to the context" do
        expect { agent.interrupt! }.not_to raise_error
      end
    end

    describe "#cancel!" do
      it "aliases #interrupt!" do
        expect { agent.cancel! }.not_to raise_error
      end
    end

    describe "#wait" do
      it "forwards to the context" do
        expect(agent.wait(:thread)).to eq([])
      end
    end

    describe "#serialize" do
      it "writes the context to a file" do
        agent.serialize(path:)
        expect(File.exist?(path)).to be(true)
      end
    end

    describe "#save" do
      it "aliases #serialize" do
        agent.save(path:)
        expect(File.exist?(path)).to be(true)
      end
    end

    describe "#deserialize" do
      it "returns the agent (enables chaining)" do
        agent.serialize(path:)
        result = agent.deserialize(path:)
        expect(result).to be(agent)
      end
    end

    describe "#restore" do
      it "aliases #deserialize and returns the agent" do
        agent.serialize(path:)
        result = agent.restore(path:)
        expect(result).to be(agent)
      end
    end
  end

  describe "#compacted?" do
    let(:agent) { described_class.new(provider) }
    let(:ctx) { agent.instance_variable_get(:@ctx) }

    it "reflects the wrapped context's compaction state" do
      expect(agent).not_to be_compacted
      ctx.compacted = true
      expect(agent).to be_compacted
    end
  end

  describe "#compactor and #compactor_options" do
    it "defaults to LLM::Compactor::Null with no options" do
      agent = described_class.new(provider)
      expect(agent.compactor).to eq(LLM::Compactor::Null)
      expect(agent.compactor_options).to eq({})
    end

    it "returns the compactor and options it was given" do
      agent = described_class.new(provider, compactor: LLM::Compactor::Truncate, compactor_options: {keep: 64})
      expect(agent.compactor).to eq(LLM::Compactor::Truncate)
      expect(agent.compactor_options).to eq({keep: 64})
      agent.compactor_options[:keep] = 1
      expect(agent.compactor_options).to eq({keep: 64})
    end
  end

  describe "tool loop concurrency" do
    let(:agent) { described_class.new(provider, mode: :responses, tools: [tool], concurrency:) }
    let(:ctx) { agent.instance_variable_get(:@ctx) }

    before do
      ctx.messages << LLM::Message.new("assistant", nil, {
        tools: [tool],
        tool_calls: [
          {id: "call_1", name: "echo", arguments: {"value" => "hello"}}
        ]
      })
    end

    context "when concurrency is a single mode" do
      context "when configured with sequential" do
        let(:concurrency) { :sequential }

        it "executes the pending tool" do
          expect(call_functions.map(&:to_h)).to eq([
            {id: "call_1", name: "echo", value: {value: "hello"}}
          ])
        end
      end

      context "when configured with thread" do
        let(:concurrency) { :thread }

        it "executes the pending tool" do
          expect(call_functions.map(&:to_h)).to eq([
            {id: "call_1", name: "echo", value: {value: "hello"}}
          ])
        end
      end

      context "when configured with fork" do
        let(:concurrency) { :fork }

        it "executes the pending tool" do
          expect(call_functions.map(&:to_h)).to eq([
            {id: "call_1", name: "echo", value: {value: "hello"}}
          ])
        end
      end

      context "when configured with ractor" do
        let(:concurrency) { :ractor }

        it "executes the pending tool" do
          expect(call_functions.map(&:to_h)).to eq([
            {id: "call_1", name: "echo", value: {value: "hello"}}
          ])
        end
      end
    end
  end

  describe "tool confirmation" do
    let(:confirmed_calls) { [] }
    let(:plain_calls) { [] }
    let(:events) { [] }
    let(:stream) do
      events = self.events
      Class.new(LLM::Stream) do
        define_method(:on_tool_return) do |tool, result|
          events << [tool.name, result.name, result.value]
        end
      end.new
    end
    let(:confirmed_tool) do
      calls = confirmed_calls
      Class.new(LLM::Tool) do
        name "confirmed"
        define_method(:call) do
          calls << :called
          {ok: true}
        end
      end
    end
    let(:plain_tool) do
      calls = plain_calls
      Class.new(LLM::Tool) do
        name "plain"
        define_method(:call) do
          calls << :called
          {ok: true}
        end
      end
    end
    let(:tools) { [confirmed_tool, plain_tool] }
    let(:agent) do
      described_class.new(
        provider, mode: :responses, tools:, confirm: ["confirmed"],
                  concurrency:, stream:
      )
    end
    let(:ctx) { agent.instance_variable_get(:@ctx) }
    let(:tool_message) do
      LLM::Message.new("assistant", nil, {
        tool_calls: [
          {id: "call_1", name: "confirmed", arguments: {}},
          {id: "call_2", name: "plain", arguments: {}}
        ],
        tools:
      })
    end

    before do
      ctx.messages << tool_message
    end

    describe "#talk" do
      let(:concurrency) { :sequential }
      let(:stub_confirmation) { true }

      before do
        allow(agent).to receive(:on_tool_confirmation, &confirmation) if stub_confirmation
      end

      context "when approval executes the confirmed tool" do
        let(:confirmation) do
          proc { |fn, strategy| fn.task(strategy).wait }
        end

        it "does not execute the confirmed tool twice" do
          call_functions
          expect(confirmed_calls.size).to eq(1)
        end

        it "still executes the unconfirmed tool once" do
          call_functions
          expect(plain_calls.size).to eq(1)
        end

        it "emits tool return callbacks once" do
          call_functions
          expect(events).to eq([
            ["confirmed", "confirmed", {ok: true}],
            ["plain", "plain", {ok: true}]
          ])
        end

        context "when concurrency is thread" do
          let(:concurrency) { :thread }

          it "does not execute the confirmed tool twice" do
            call_functions
            expect(confirmed_calls.size).to eq(1)
          end

          it "still executes the unconfirmed tool once" do
            call_functions
            expect(plain_calls.size).to eq(1)
          end
        end
      end

      context "when approval cancels the confirmed tool" do
        let(:confirmation) do
          proc { |fn, _strategy| fn.cancel(reason: "approval required") }
        end

        it "does not execute the confirmed tool" do
          call_functions
          expect(confirmed_calls).to be_empty
        end

        it "still executes the unconfirmed tool once" do
          call_functions
          expect(plain_calls.size).to eq(1)
        end

        it "emits cancelled and unconfirmed tool return callbacks" do
          call_functions
          expect(events).to eq([
            ["confirmed", "confirmed", {cancelled: true, reason: "approval required"}],
            ["plain", "plain", {ok: true}]
          ])
        end
      end

      context "when on_tool_confirmation is private" do
        let(:stub_confirmation) { false }
        let(:agent_class) do
          tool_classes = tools
          Class.new(described_class) do
            private
            define_method(:on_tool_confirmation) do |fn, strategy|
              fn.task(strategy).wait
            end
          end.tap do |klass|
            klass.tools(*tool_classes)
            klass.confirm("confirmed")
          end
        end
        let(:agent) { agent_class.new(provider, mode: :responses, concurrency:) }

        it "still invokes the callback" do
          call_functions
          expect(confirmed_calls.size).to eq(1)
        end
      end
    end
  end

  describe "DSL tracer scoping" do
    let(:tracer) { LLM::Tracer::Null.new(provider) }
    let(:res) { response!(choices: [LLM::Message.new("assistant", "hello")]) }
    let(:responses) { provider.responses }
    let(:tool) do
      Class.new(LLM::Tool) do
        name "echo"
        description "Echo a value"
        param :value, String, "Value", required: true

        def call(value:) = {value:}
      end
    end
    let(:agent) do
      tracer = self.tracer
      tool_class = tool
      Class.new(described_class) do
        tools tool_class
        tracer { tracer }
      end.new(provider, mode: :responses)
    end

    describe "#talk" do
      it "scopes the tracer to the turn" do
        allow(provider).to receive(:responses).and_return(responses)
        expect(responses).to receive(:create) do
          expect(provider.tracer).to equal(tracer)
          res
        end
        agent.talk("hello")
        expect(provider.tracer).to be_a(LLM::Tracer::Null)
      end
    end

    describe "#functions" do
      subject(:functions) { agent.pending_functions }

      let(:message) do
        LLM::Message.new("assistant", nil, {
          tool_calls: [
            {id: "call_1", name: "echo", arguments: {value: "hello"}}
          ],
          tools: [tool]
        })
      end

      before do
        agent.messages << message
      end

      it "scopes the tracer to pending function access" do
        expect(functions.size).to eq(1)
        expect(functions.first.tracer).to equal(tracer)
        expect(provider.tracer).to be_a(LLM::Tracer::Null)
      end
    end
  end

  describe "tool budget" do
    let(:responses) { provider.responses }
    let(:tool) do
      Class.new(LLM::Tool) do
        @calls = 0
        class << self
          attr_accessor :calls
        end
        name "echo"
        description "Echo a value"
        param :value, String, "Value", required: true
        def call(value:)
          self.class.calls += 1
          {value:}
        end
      end
    end
    let(:agent) { described_class.new(provider, mode: :responses, tools: [tool], stream:) }
    let(:ctx) { agent.instance_variable_get(:@ctx) }
    let(:stream) do
      recorder = returned
      LLM::Stream.new.tap do |stream|
        stream.define_singleton_method(:on_tool_return) { |_tool, result| recorder << result }
      end
    end
    let(:returned) { [] }
    let(:final_response) do
      response!(choices: [LLM::Message.new("assistant", "done")])
    end
    let(:advisory) do
      an_object_having_attributes(
        value: hash_including(
          cancelled: true,
          reason: /too many tool calls/
        )
      )
    end
    let(:advisories) do
      ctx.messages.map(&:content).flatten.select do
        it.respond_to?(:value) && it.value.is_a?(Hash) &&
          it.value[:cancelled] == true &&
          it.value[:reason].to_s.include?("too many tool calls")
      end
    end
    let(:tool_budget) { nil }
    let(:returns) { [tool_call_response("call_1"), final_response] }

    before do
      allow(provider).to receive(:responses).and_return(responses)
      tool.calls = 0
      expect(responses).to receive(:create).and_return(*returns)
      agent.talk("hello", tool_budget:)
    end

    context "when the tool budget is spent" do
      let(:tool_budget) { 2 }
      let(:returns) do
        [
          tool_call_response("call_1"),
          tool_call_response("call_2"),
          tool_call_response("call_3"),
          tool_call_response("call_4"),
          final_response
        ]
      end

      it "sends an advisory message" do
        expect(ctx.messages.map(&:content).flatten).to include(advisory)
      end

      it "runs no more tool calls than the budget allows" do
        expect(tool.calls).to eq(2)
      end
    end

    context "when a model keeps asking for tools" do
      let(:tool_budget) { 1 }
      let(:returns) do
        [
          tool_call_response("call_1"),
          tool_call_response("call_2"),
          tool_call_response("call_3"),
          tool_call_response("call_4"),
          final_response
        ]
      end

      it "runs no more tool calls than the budget allows" do
        expect(tool.calls).to eq(1)
      end

      it "sends an advisory for each extra request" do
        expect(advisories.size).to eq(3)
      end

      it "returns every call to the stream, refused or not" do
        expect(returned.size).to eq(4)
      end

      it "returns each refused call as an advisory" do
        expect(returned.count { it.value[:cancelled] }).to eq(3)
      end
    end

    context "when one message requests a batch of calls" do
      let(:tool_budget) { 1 }
      let(:returns) { [batch_tool_call_response(%w[call_1 call_2]), final_response] }

      it "runs none of the batched calls" do
        expect(tool.calls).to eq(0)
      end

      it "sends one advisory per call in the batch" do
        expect(advisories.size).to eq(2)
      end
    end

    context "when no tool budget is set" do
      let(:tool_budget) { nil }

      it "does not send an advisory" do
        expect(ctx.messages.map(&:content).flatten).not_to include(advisory)
      end
    end

    context "when the budget is not exhausted" do
      let(:tool_budget) { 5 }
      let(:returns) do
        [tool_call_response("call_1"), tool_call_response("call_2"), final_response]
      end

      it "runs the tools freely" do
        expect(tool.calls).to eq(2)
      end

      it "sends no advisories" do
        expect(advisories).to be_empty
      end
    end
  end

  context "when given openai" do
    let(:provider) { LLM.openai(key: "test") }
    include_examples "agent behavior"
  end

  context "when given google" do
    let(:provider) { LLM.google(key: "test") }
    include_examples "agent behavior"
  end

  context "when given anthropic" do
    let(:provider) { LLM.anthropic(key: "test") }
    include_examples "agent behavior"
  end

  context "when given xai" do
    let(:provider) { LLM.xai(key: "test") }
    include_examples "agent behavior"
  end

  context "when given zai" do
    let(:provider) { LLM.zai(key: "test") }
    include_examples "agent behavior"
  end

  context "when given deepseek" do
    let(:provider) { LLM.deepseek(key: "test") }
    include_examples "agent behavior"
  end

  describe "tracer lifecycle" do
    let(:provider) { LLM.openai(key: "test") }
    let(:responses) { provider.responses }
    let(:response) { response!(choices: [LLM::Message.new("assistant", "hi")]) }
    let(:exits) { [] }
    let(:tracer) do
      exits = self.exits
      Class.new(LLM::Tracer::Null) do
        define_method(:on_exit) { exits << :exit }
      end.new(provider)
    end
    let(:tools) { [] }
    let(:agent) { described_class.new(provider, model: "gpt-5.4", tracer:, tools:) }
    let(:returns) { [response] }

    before do
      allow(provider).to receive(:responses).and_return(responses)
      allow(responses).to receive(:create).and_return(*returns)
      agent.talk("hello")
    end

    it "releases the tracer once, at the end of the turn" do
      expect(exits.size).to eq(1)
    end

    context "when the turn runs a tool" do
      let(:tool) do
        Class.new(LLM::Tool) do
          name "echo"
          description "Echo a value"
          param :value, String, "Value", required: true
          def call(value:) = {value:}
        end
      end
      let(:tools) { [tool] }
      let(:tool_call) do
        response!(choices: [LLM::Message.new("assistant", nil, {
          tools: [tool],
          tool_calls: [{id: "call_1", name: "echo", arguments: {"value" => "hi"}}]
        })])
      end
      let(:returns) { [tool_call, response] }

      it "releases the tracer once, at the end of the turn" do
        expect(exits.size).to eq(1)
      end

      context "when the tool runs on another thread" do
        let(:agent) do
          described_class.new(provider, model: "gpt-5.4", tracer:, tools:, concurrency: :thread)
        end
        let(:resource) { [] }
        let(:writes) { [] }
        let(:tracer) do
          resource = self.resource
          writes = self.writes
          Class.new(LLM::Tracer::Null) do
            define_method(:on_tool_start) { |**_opts| resource << :resource; :span }
            define_method(:on_tool_finish) { |**_opts| writes << (resource.empty? ? :lost : :written) }
            define_method(:on_exit) { resource.clear }
          end.new(provider)
        end

        it "keeps the tracer's resource until the turn ends" do
          expect(writes).to eq([:written])
        end
      end
    end
  end

  describe "intercept" do
    let(:llm) { LLM.openai(key: "test") }
    let(:intercept) { LLM::Intercept::Null.new(llm) }

    context "when given an object" do
      let(:agent) { described_class.new(llm, intercept:) }

      it "is forwarded to the context" do
        expect(wrapped_context(agent).intercept).to equal(intercept)
      end
    end

    context "when given a block" do
      let(:agent) do
        value = intercept
        Class.new(described_class) { intercept { value } }.new(llm)
      end

      it "is resolved and forwarded to the context" do
        expect(wrapped_context(agent).intercept).to equal(intercept)
      end
    end

    context "when given to the set method" do
      let(:agent) do
        value = intercept
        Class.new(described_class) { set intercept: proc { value } }.new(llm)
      end

      it "is forwarded to the context" do
        expect(wrapped_context(agent).intercept).to equal(intercept)
      end
    end
  end

  def call_functions
    agent.send(:call_functions)
  end

  def tool_call_response(id)
    response!(choices: [
      LLM::Message.new("assistant", nil, {
        tools: [tool],
        tool_calls: [{id:, name: "echo", arguments: {"value" => "hello"}}]
      })
    ])
  end

  def batch_tool_call_response(ids)
    response!(choices: [
      LLM::Message.new("assistant", nil, {
        tools: [tool],
        tool_calls: ids.map do
          {id: it, name: "echo", arguments: {"value" => "hello"}}
        end
      })
    ])
  end

  def wrapped_context(agent)
    agent.instance_variable_get(:@ctx)
  end
end

RSpec.describe LLM::Agent, "class-level configuration" do
  let(:provider) { LLM.openai(key: "test") }

  let(:klass) do
    Class.new(LLM::Agent) do
      description :described_here

      def described_here = "the agent's own words"
    end
  end

  it "hands a Symbol back for an instance to resolve" do
    expect(klass.description).to eq(:described_here)
  end
  it "resolves it on the instance" do
    expect(klass.new(provider).description).to eq("the agent's own words")
  end
  it "passes a configured compactor class to the context" do
    agent_class = Class.new(LLM::Agent) do
      compactor LLM::Compactor::Truncate
    end

    agent = agent_class.new(provider)
    ctx = agent.instance_variable_get(:@ctx)

    expect(ctx.instance_variable_get(:@compactor)[:klass])
      .to eq(LLM::Compactor::Truncate)
  end

  it "resolves a Symbol compactor on the instance" do
    agent_class = Class.new(LLM::Agent) do
      compactor :configured_compactor

      def configured_compactor = LLM::Compactor::Truncate
    end

    agent = agent_class.new(provider)
    ctx = agent.instance_variable_get(:@ctx)

    expect(ctx.instance_variable_get(:@compactor)[:klass])
      .to eq(LLM::Compactor::Truncate)
  end

  it "resolves a Proc compactor on the instance" do
    agent_class = Class.new(LLM::Agent) do
      compactor { LLM::Compactor::Truncate }
    end

    agent = agent_class.new(provider)
    ctx = agent.instance_variable_get(:@ctx)

    expect(ctx.instance_variable_get(:@compactor)[:klass])
      .to eq(LLM::Compactor::Truncate)
  end

  it "passes compactor options to the context" do
    agent_class = Class.new(LLM::Agent) do
      compactor LLM::Compactor::Truncate
      compactor_options keep: 10
    end
    agent = agent_class.new(provider)
    ctx = agent.instance_variable_get(:@ctx)

    expect(ctx.instance_variable_get(:@compactor)[:options])
      .to eq(keep: 10)
  end
end
