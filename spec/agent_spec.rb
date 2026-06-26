# frozen_string_literal: true

require_relative "setup"

RSpec.describe LLM::Agent do
  let(:provider) { LLM.openai(key: "test") }
  let(:empty_functions) { [].extend(LLM::Function::Array) }

  shared_examples "agent behavior" do
    let(:schema) do
      Class.new(LLM::Schema) do
        property :answer, String, "Answer", required: true
      end
    end

    let(:tool) do
      Class.new(LLM::Tool) do
        name "echo"
        description "Echo a value"
        param :value, String, "Value", required: true
        def call(value:) = {value:}
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
      it "passes DSL defaults to the context" do
        expect(LLM::Context).to receive(:new).with(
          provider,
          {model: "gpt-4.1", tools: [tool], schema:, guard: true}
        ).and_call_original
        agent_class.new(provider)
      end

      it "keeps concurrency on the agent" do
        klass = Class.new(described_class) do
          model "gpt-4.1"
          concurrency :thread
        end
        expect(LLM::Context).to receive(:new).with(
          provider,
          {model: "gpt-4.1", tools: [], guard: true}
        ).and_call_original
        expect(klass.new(provider).concurrency).to eq(:thread)
      end

      it "passes DSL skills to the context" do
        skill_path = "/tmp/weather"
        skill = double("skill", to_tool: tool)
        klass = Class.new(described_class) do
          model "gpt-4.1"
          skills skill_path
        end
        expect(LLM::Skill).to receive(:load).with(skill_path).and_return(skill)
        expect(LLM::Context).to receive(:new).with(
          provider,
          {model: "gpt-4.1", tools: [], skills: [skill_path], guard: true}
        ).and_call_original
        klass.new(provider)
      end

      context "when model is declared with a block" do
        let(:klass) do
          Class.new(described_class) do
            model { "gpt-4.1" }
          end
        end

        it "resolves the block against the agent instance" do
          expect(LLM::Context).to receive(:new).with(
            provider,
            {model: "gpt-4.1", tools: [], guard: true}
          ).and_call_original
          klass.new(provider)
        end
      end

      context "when no model is configured" do
        it "keeps the provider default model" do
          expect(LLM::Context).to receive(:new).with(
            provider,
            {tools: [], guard: true}
          ).and_call_original
          described_class.new(provider)
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
          expect(LLM::Context).to receive(:new).with(
            provider,
            {tools: [tool], guard: true}
          ).and_call_original
          klass.new(provider)
        end
      end

      context "when skills are declared with a block" do
        let(:skill_path) { "/tmp/weather" }
        let(:skill) { double("skill", to_tool: tool) }
        let(:klass) do
          skill_path = self.skill_path
          Class.new(described_class) do
            skills { [skill_path] }
          end
        end

        it "resolves the block against the agent instance" do
          expect(LLM::Skill).to receive(:load).with(skill_path).and_return(skill)
          expect(LLM::Context).to receive(:new).with(
            provider,
            {tools: [], skills: [skill_path], guard: true}
          ).and_call_original
          klass.new(provider)
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
          expect(LLM::Context).to receive(:new).with(
            provider,
            {tools: [], guard: true, schema: schema}
          ).and_call_original
          klass.new(provider)
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
          expect(LLM::Context).to receive(:new).with(
            provider,
            {model: "gpt-4.1", tools: [], guard: true, stream:}
          ).and_call_original
          klass.new(provider)
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
          let(:first_stream) { first_agent.instance_variable_get(:@ctx).send(:stream) }
          let(:second_stream) { second_agent.instance_variable_get(:@ctx).send(:stream) }

          it "creates a separate stream per agent instance" do
            expect(first_stream).not_to equal(second_stream)
          end

          it "uses the configured stream type" do
            expect(first_stream).to be_a(stream_class)
            expect(second_stream).to be_a(stream_class)
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
          expect(LLM::Context).to receive(:new).with(
            provider,
            {model: "gpt-4.1", tools: [], guard: true, stream:}
          ).and_call_original
          klass.new(provider)
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

      it "sends the prompt through the provider" do
        if provider.name == :openai
          allow(agent.llm).to receive(:responses).and_return(responses)
          expect(responses).to receive(:create)
            .with(prompt, instance_of(Hash))
            .and_return(double(choices: [LLM::Message.new("assistant", "hello")]))
        else
          expect(agent.llm).to receive(:complete)
            .with(prompt, instance_of(Hash))
            .and_return(double(choices: [LLM::Message.new("assistant", "hello")]))
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
              .with(expected_prompt, hash_including(input: existing_messages))
              .and_return(double(choices: [LLM::Message.new("assistant", "hello")]))
          else
            expect(agent.llm).to receive(:complete)
              .with(expected_prompt, hash_including(messages: existing_messages))
              .and_return(double(choices: [LLM::Message.new("assistant", "hello")]))
          end
          agent.talk("hello")
        end
      end
    end
  end

  describe "context parity" do
    let(:returns) { [double("return")] }
    let(:usage) { LLM::Object.from(input_tokens: 1, output_tokens: 2, total_tokens: 3) }
    let(:messages) { double("messages") }
    let(:functions) { empty_functions }
    let(:cost) { double("cost") }
    let(:payload) { {"schema_version" => 1, "model" => "gpt-4.1", "messages" => []} }
    let(:params) { {model: "gpt-4.1"} }
    let(:ctx) do
      instance_double(
        LLM::Context,
        messages:,
        functions:,
        returns:,
        usage:,
        mode: :completions,
        cost:,
        context_window: 128_000,
        model: "gpt-4.1",
        to_h: payload,
        params:,
        prompt: :prompt,
        image_url: :image,
        local_file: :local_file,
        remote_file: :remote_file,
        tracer: :tracer
      )
    end
    let(:agent) { described_class.new(provider) }

    before do
      allow(LLM::Context).to receive(:new).and_return(ctx)
      allow(ctx).to receive(:interrupt!)
      allow(ctx).to receive(:wait).with(:call).and_return(returns)
      allow(ctx).to receive(:wait).with(:thread).and_return(returns)
    end

    describe "#messages" do
      subject { agent.messages }
      it { is_expected.to be(messages) }
    end

    describe "#functions" do
      subject { agent.functions }
      it { is_expected.to be(functions) }
    end

    describe "#returns" do
      subject { agent.returns }
      it { is_expected.to be(returns) }
    end

    describe "#usage" do
      subject { agent.usage }
      it { is_expected.to be(usage) }
    end

    describe "#mode" do
      subject { agent.mode }
      it { is_expected.to eq(:completions) }
    end

    describe "#cost" do
      subject { agent.cost }
      it { is_expected.to be(cost) }
    end

    describe "#context_window" do
      subject { agent.context_window }
      it { is_expected.to eq(128_000) }
    end

    describe "#model" do
      subject { agent.model }
      it { is_expected.to eq("gpt-4.1") }
    end

    describe "#to_h" do
      subject { agent.to_h }
      it { is_expected.to eq(payload) }
    end

    describe "#to_json" do
      subject { agent.to_json }
      it { is_expected.to eq(payload.to_json) }
    end

    describe "#prompt" do
      it "forwards to the context" do
        expect(agent.prompt {}).to eq(:prompt)
      end
    end

    describe "#image_url" do
      it "forwards to the context" do
        expect(agent.image_url("https://example.com")).to eq(:image)
      end
    end

    describe "#local_file" do
      it "forwards to the context" do
        expect(agent.local_file("/tmp/x")).to eq(:local_file)
      end
    end

    describe "#remote_file" do
      it "forwards to the context" do
        expect(agent.remote_file(:response)).to eq(:remote_file)
      end
    end

    describe "#tracer" do
      subject { agent.tracer }
      it { is_expected.to eq(:tracer) }
    end

    describe "#params" do
      subject { agent.params }
      it { is_expected.to eq(params) }
    end

    describe "#interrupt!" do
      it "forwards to the context" do
        agent.interrupt!
        expect(ctx).to have_received(:interrupt!)
      end
    end

    describe "#cancel!" do
      it "aliases #interrupt!" do
        agent.cancel!
        expect(ctx).to have_received(:interrupt!)
      end
    end

    describe "#wait" do
      it "forwards to the context" do
        expect(agent.wait(:thread)).to eq(returns)
      end
    end
  end

  describe "tool loop concurrency" do
    let(:tool_return) { double("return") }
    let(:pending_functions) { [double("function")].extend(LLM::Function::Array) }
    let(:ctx) do
      instance_double(
        LLM::Context,
        messages: [],
        functions: pending_functions,
        returns: [],
        usage: LLM::Object.from(input_tokens: 0, output_tokens: 0, total_tokens: 0),
        mode: :responses,
        cost: double("cost"),
        context_window: 0,
        model: "gpt-4.1",
        params: {},
        functions?: false,
        to_h: {"schema_version" => 1, "model" => "gpt-4.1", "messages" => []},
        prompt: nil,
        image_url: nil,
        local_file: nil,
        remote_file: nil,
        tracer: nil
      )
    end

    before do
      allow(LLM::Context).to receive(:new).and_return(ctx)
      allow(ctx).to receive(:talk).and_return(double("first_response"), double("second_response"))
      allow(ctx).to receive(:wait)
      allow(ctx).to receive(:functions?).and_return(true, true, false, false)
      allow(ctx).to receive(:functions).and_return(pending_functions, pending_functions, empty_functions, empty_functions)
    end

    describe "#talk" do
      it "uses sequential calls by default" do
        agent = described_class.new(provider, mode: :responses)
        allow(ctx).to receive(:wait).with(:call).and_return([tool_return])
        agent.talk("hello")
        expect(ctx).to have_received(:wait).with(:call)
        expect(ctx).to have_received(:talk).with("hello", {})
        expect(ctx).to have_received(:talk).with([tool_return], {})
      end

      shared_examples "single-mode concurrency" do
        it "uses the configured concurrency for tool loops" do
          allow(ctx).to receive(:wait).with(concurrency).and_return([tool_return])
          agent.talk("hello")
          expect(ctx).to have_received(:wait).with(concurrency)
          expect(ctx).to have_received(:talk).with("hello", {})
          expect(ctx).to have_received(:talk).with([tool_return], {})
        end
      end

      let(:agent) { described_class.new(provider, mode: :responses, concurrency:) }

      context "when concurrency is a single mode" do
        context "when configured with thread" do
          let(:concurrency) { :thread }
          include_examples "single-mode concurrency"
        end

        context "when configured with fork" do
          let(:concurrency) { :fork }
          include_examples "single-mode concurrency"
        end
      end

      context "when concurrency is a list of queued task types" do
        let(:concurrency) { [:thread, :ractor] }

        it "waits for the configured task types" do
          allow(ctx).to receive(:wait).with([:thread, :ractor]).and_return([tool_return])
          agent.talk("hello")
          expect(ctx).to have_received(:wait).with([:thread, :ractor])
          expect(ctx).to have_received(:talk).with("hello", {})
          expect(ctx).to have_received(:talk).with([tool_return], {})
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
      let(:concurrency) { :call }
      let(:stub_confirmation) { true }

      before do
        allow(agent).to receive(:on_tool_confirmation, &confirmation) if stub_confirmation
      end

      context "when approval executes the confirmed tool" do
        let(:confirmation) do
          proc { |fn, strategy| fn.spawn(strategy).wait }
        end

        it "does not execute the confirmed tool twice" do
          agent.send(:call_functions)
          expect(confirmed_calls.size).to eq(1)
        end

        it "still executes the unconfirmed tool once" do
          agent.send(:call_functions)
          expect(plain_calls.size).to eq(1)
        end

        it "emits tool return callbacks once" do
          agent.send(:call_functions)
          expect(events).to eq([
            ["confirmed", "confirmed", {ok: true}],
            ["plain", "plain", {ok: true}]
          ])
        end

        context "when concurrency is thread" do
          let(:concurrency) { :thread }

          it "does not execute the confirmed tool twice" do
            agent.send(:call_functions)
            expect(confirmed_calls.size).to eq(1)
          end

          it "still executes the unconfirmed tool once" do
            agent.send(:call_functions)
            expect(plain_calls.size).to eq(1)
          end
        end
      end

      context "when approval cancels the confirmed tool" do
        let(:confirmation) do
          proc { |fn, _strategy| fn.cancel(reason: "approval required") }
        end

        it "does not execute the confirmed tool" do
          agent.send(:call_functions)
          expect(confirmed_calls).to be_empty
        end

        it "still executes the unconfirmed tool once" do
          agent.send(:call_functions)
          expect(plain_calls.size).to eq(1)
        end

        it "emits cancelled and unconfirmed tool return callbacks" do
          agent.send(:call_functions)
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
              fn.spawn(strategy).wait
            end
          end.tap do |klass|
            klass.tools(*tool_classes)
            klass.confirm("confirmed")
          end
        end
        let(:agent) { agent_class.new(provider, mode: :responses, concurrency:) }

        it "still invokes the callback" do
          agent.send(:call_functions)
          expect(confirmed_calls.size).to eq(1)
        end
      end
    end
  end

  describe "DSL tracer scoping" do
    let(:tracer) { LLM::Tracer::Null.new(provider) }
    let(:res) { Struct.new(:choices).new([LLM::Message.new("assistant", "hello")]) }
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
      subject(:functions) { agent.functions }

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

  describe "tool attempt limit" do
    let(:tool) do
      Class.new(LLM::Tool) do
        name "echo"
        description "Echo a value"
      end
    end
    let(:pending_function) do
      fn = tool.function
      fn.id = "call_1"
      fn.arguments = {value: "hello"}
      fn
    end
    let(:pending_functions) { [pending_function].extend(LLM::Function::Array) }
    let(:ctx) do
      instance_double(
        LLM::Context,
        messages: [],
        functions: pending_functions,
        returns: [],
        usage: LLM::Object.from(input_tokens: 0, output_tokens: 0, total_tokens: 0),
        mode: :completions,
        cost: double("cost"),
        context_window: 0,
        model: "gpt-4.1",
        to_h: {"schema_version" => 1, "model" => "gpt-4.1", "messages" => []},
        prompt: nil,
        image_url: nil,
        local_file: nil,
        remote_file: nil,
        params: {},
        functions?: false,
        tracer: nil
      )
    end
    let(:agent) { described_class.new(provider) }
    let(:advisory_res) { double("advisory_response") }
    let(:res) { double("final_response") }

    before do
      allow(LLM::Context).to receive(:new).and_return(ctx)
      allow(ctx).to receive(:talk).and_return(double("first_response"), *Array.new(25) { double("response") }, advisory_res, res)
      allow(ctx).to receive(:wait).with(:call).and_return([double("return")])
      allow(ctx).to receive(:functions?).and_return(*Array.new(29, true), false, false, false)
      allow(ctx).to receive(:functions).and_return(*Array.new(30, pending_functions), empty_functions, empty_functions, empty_functions)
    end

    it "defaults to 25 tool loop attempts" do
      expect(agent.talk("hello")).to eq(res)
      expect(ctx).to have_received(:wait).with(:call).exactly(26).times
      expect(ctx).to have_received(:talk).with([
        LLM::Function::Return.new("call_1", "echo", {
          error: true,
          type: LLM::ToolLoopError.name,
          message: "tool loop rate limit reached"
        })
      ], {})
    end

    it "disables advisory tool-limit returns when tool_attempts is nil" do
      allow(ctx).to receive(:talk).and_return(double("first_response"), res)
      allow(ctx).to receive(:functions?).and_return(true, false, false)
      allow(ctx).to receive(:functions).and_return(pending_functions, empty_functions, empty_functions)
      expect(agent.talk("hello", tool_attempts: nil)).to eq(res)
      expect(ctx).to have_received(:wait).with(:call).once
      expect(ctx).not_to have_received(:talk).with([
        LLM::Function::Return.new("call_1", "echo", {
          error: true,
          type: LLM::ToolLoopError.name,
          message: "tool loop rate limit reached"
        })
      ], {tool_attempts: nil})
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
end
