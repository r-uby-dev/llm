# frozen_string_literal: true

require "setup"
require "fileutils"
require "tempfile"
require "tmpdir"

RSpec.describe LLM::Context do
  let(:ctx) { LLM::Context.new(provider, model:) }

  context "when given openai" do
    let(:provider) { LLM.openai(key: "test") }
    let(:model) { "gpt-5.4" }

    context "#cost" do
      let(:cost) { LLM::Cost.new(input_costs: 0.000728125) }

      before do
        ctx.usage.input_tokens = 100
        ctx.usage.output_tokens = 50
        ctx.usage.cache_read_tokens = 25
        ctx.usage.reasoning_tokens = 10
      end

      it "delegates cost construction to LLM::Cost" do
        expect(LLM::Cost).to receive(:from).with(ctx).and_return(cost)
        expect(ctx.cost).to be(cost)
      end
    end

    context "#context_window" do
      subject { ctx.context_window }
      it { is_expected.to eq(1050000) }
    end

    context "#params" do
      subject { ctx.params }
      it { is_expected.to include(model:) }
    end

    context "#wait" do
      let(:events) { [] }
      let(:stream) do
        events = self.events
        Class.new(LLM::Stream) do
          define_method(:on_tool_return) do |tool, result|
            events << [tool.name, result.name, result.value]
          end
        end.new
      end
      let(:ctx) { LLM::Context.new(provider, model:, stream:) }
      let(:function) do
        LLM::Function.new("system") do |fn|
          fn.define { {ok: true} }
        end.tap do |fn|
          fn.id = "call_1"
          fn.arguments = {}
        end
      end

      before do
        allow(ctx).to receive(:functions).and_return([function].extend(LLM::Function::Array))
      end

      it "emits tool return callbacks for direct waits" do
        ctx.wait(:call)
        expect(events).to eq([["system", "system", {ok: true}]])
      end
    end

    context "#ask" do
      let(:response) { double(content: "Hello") }

      context "when given a plain prompt" do
        before do
          allow(ctx).to receive(:talk).with("Hello?").and_return(response)
        end

        it "returns the response" do
          expect(ctx.ask("Hello?")).to eq(response)
        end
      end

      context "when given file attachments" do
        let(:tempfile) do
          Tempfile.new(["llmrb", ".pdf"]).tap do |file|
            file.write("%PDF-1.4")
            file.flush
          end
        end
        let(:file_prompt) { ["What is this?", [ctx.local_file(tempfile.path)]] }

        before do
          allow(ctx).to receive(:talk).with(file_prompt).and_return(response)
        end

        after do
          tempfile.close!
        end

        it "attaches the local file to the prompt" do
          expect(ctx.ask("What is this?", with: tempfile.path)).to eq(response)
        end
      end

      context "when given a stream target" do
        let(:stream) { StringIO.new }

        before do
          allow(ctx).to receive(:talk).with("Hello?", stream:).and_return(response)
        end

        it "forwards the stream target" do
          expect(ctx.ask("Hello?", stream:)).to eq(response)
        end
      end
    end
  end

  context "when given anthropic" do
    let(:provider) { LLM.anthropic(key: "test") }
    let(:model) { "claude-sonnet-4-20250514" }

    context "#context_window" do
      subject { ctx.context_window }
      it { is_expected.to eq(200000) }
    end
  end

  context "when given google" do
    let(:provider) { LLM.google(key: "test") }
    let(:model) { "gemini-2.5-flash" }

    context "#context_window" do
      subject { ctx.context_window }
      it { is_expected.to eq(1048576) }
    end
  end

  context "when given deepseek" do
    let(:provider) { LLM.deepseek(key: "test") }
    let(:model) { "deepseek-chat" }

    context "#context_window" do
      subject { ctx.context_window }
      it { is_expected.to eq(1000000) }
    end
  end

  context "when given a model that does not exist" do
    let(:provider) { LLM.deepseek(key: "test") }
    let(:model) { "does-not-exist" }

    context "#context_window" do
      subject { ctx.context_window }
      it { is_expected.to be_zero }
    end
  end

  context "when configured with responses mode" do
    let(:provider) { LLM.openai(key: "test") }
    let(:model) { "gpt-5.4" }
    let(:ctx) { LLM::Context.new(provider, model:, mode: :responses) }
    let(:responses) { double }
    let(:response) { double(choices: [LLM::Message.new("assistant", "Paris")]) }

    it "routes talk through the responses API" do
      allow(provider).to receive(:responses).and_return(responses)
      expect(responses).to receive(:create).with("What is the capital of France?", hash_including(model:))
        .and_return(response)
      expect(ctx.talk("What is the capital of France?")).to eq(response)
    end

    it "compacts before sending a responses request" do
      compactor = instance_double(LLM::Compactor, compact?: true, compact!: nil)
      allow(ctx).to receive(:compactor).and_return(compactor)
      allow(provider).to receive(:responses).and_return(responses)
      expect(compactor).to receive(:compact?).with("What is the capital of France?").ordered.and_return(true)
      expect(compactor).to receive(:compact!).with("What is the capital of France?").ordered.and_return(nil)
      expect(responses).to receive(:create).ordered.and_return(response)
      ctx.talk("What is the capital of France?")
    end
  end

  context "when configured with skills" do
    let(:provider) { LLM.openai(key: "test") }
    let(:model) { "gpt-5.4" }
    let(:skill_path) { "/tmp/weather" }
    let(:tool) { double("tool") }
    let(:skill) { double("skill") }

    it "loads skills into tools" do
      expect(LLM::Skill).to receive(:load).with(skill_path).and_return(skill)
      expect(skill).to receive(:to_tool).with(instance_of(described_class)).and_return(tool)
      ctx = described_class.new(provider, model:, skills: [skill_path])
      expect(ctx.instance_variable_get(:@params)[:tools]).to eq([tool])
    end
  end

  context "when serializing tagged prompt objects" do
    let(:provider) { LLM.openai(key: "test") }
    let(:model) { "gpt-5.4" }
    let(:image_url) { "https://example.com/cat.png" }
    let(:remote_file) do
      LLM::Object.from(
        "file?" => true,
        "id" => "file_123",
        "filename" => "photo.png",
        "mime_type" => "image/png",
        "uri" => "https://example.com/photo.png",
        "file_type" => "image"
      )
    end
    let(:tempfile) do
      Tempfile.new(["llmrb", ".txt"]).tap do |file|
        file.write("hello")
        file.flush
      end
    end
    let(:tmpdir) { Dir.mktmpdir("llmrb-context") }
    let(:serialized) { File.join(tmpdir, "context.json") }
    let(:message) do
      LLM::Message.new("user", [
        ctx.image_url(image_url),
        ctx.local_file(tempfile.path),
        ctx.remote_file(remote_file)
      ])
    end
    let(:restored) do
      described_class.new(provider, model:).tap do |other|
        ctx.messages << message
        other.restore(string: ctx.to_json)
      end
    end
    let(:content) { restored.messages.first.content }

    after do
      tempfile.close!
      FileUtils.remove_entry(tmpdir)
    end

    context "#restore" do
      it "restores image_url content" do
        expect(content.fetch(0).kind).to eq(:image_url)
        expect(content.fetch(0).value).to eq(image_url)
      end

      it "restores local_file content" do
        expect(content.fetch(1).kind).to eq(:local_file)
        expect(content.fetch(1).value).to be_a(LLM::File)
        expect(content.fetch(1).value.path).to eq(tempfile.path)
      end

      it "restores remote_file content" do
        expect(content.fetch(2).kind).to eq(:remote_file)
        expect(content.fetch(2).value.file?).to eq(true)
        expect(content.fetch(2).value.id).to eq("file_123")
        expect(content.fetch(2).value.filename).to eq("photo.png")
        expect(content.fetch(2).value.mime_type).to eq("image/png")
        expect(content.fetch(2).value.uri).to eq("https://example.com/photo.png")
        expect(content.fetch(2).value.file_type).to eq("image")
      end
    end

    context "#serialize" do
      let(:restored) do
        described_class.new(provider, model:).tap do |other|
          ctx.messages << message
          ctx.serialize(path: serialized)
          other.restore(path: serialized)
        end
      end

      it "round-trips tagged prompt objects through a file" do
        expect(restored.messages.size).to eq(1)
        expect(restored.messages.first).to be_a(LLM::Message)
        expect(content.fetch(0).kind).to eq(:image_url)
        expect(content.fetch(0).value).to eq(image_url)
        expect(content.fetch(1).kind).to eq(:local_file)
        expect(content.fetch(1).value).to be_a(LLM::File)
        expect(content.fetch(1).value.path).to eq(tempfile.path)
        expect(content.fetch(2).kind).to eq(:remote_file)
        expect(content.fetch(2).value.file?).to eq(true)
        expect(content.fetch(2).value.id).to eq("file_123")
      end

      context "with assistant tool calls" do
        let(:message) do
          LLM::Message.new("assistant", nil, {
            tool_calls: [
              {id: "call_1", name: "system", arguments: {command: "date"}}
            ],
            original_tool_calls: [
              {"id" => "call_1", "type" => "function", "function" => {"name" => "system", "arguments" => "{\"command\":\"date\"}"}}
            ]
          })
        end
        before do
          restored
        end
        let(:restored_message) { restored.messages.first }
        let(:serialized_message) { JSON.parse(File.read(serialized)).fetch("messages").fetch(0) }
        let(:tool_calls) do
          restored_message.extra[:tool_calls].map do |tool|
            tool.to_h.merge("arguments" => tool.arguments.to_h)
          end
        end
        let(:original_tool_calls) do
          restored_message.extra[:original_tool_calls].map do |tool|
            tool.to_h.merge("function" => tool.function.to_h)
          end
        end

        it "restores the message as a tool call" do
          expect(restored_message.tool_call?).to eq(true)
        end

        it "serializes parsed tool calls under the tools key" do
          expect(serialized_message.fetch("tools")).to eq([
            {"id" => "call_1", "name" => "system", "arguments" => {"command" => "date"}}
          ])
        end

        it "round-trips parsed tool calls" do
          expect(tool_calls).to eq([
            {"id" => "call_1", "name" => "system", "arguments" => {"command" => "date"}}
          ])
        end

        it "round-trips original tool calls" do
          expect(original_tool_calls).to eq([
            {"id" => "call_1", "type" => "function", "function" => {"name" => "system", "arguments" => "{\"command\":\"date\"}"}}
          ])
        end
      end
    end
  end

  context "when a tool call already has a matching tool return" do
    let(:provider) { LLM.openai(key: "test") }
    let(:model) { "gpt-5.4" }
    let(:tool) do
      Class.new(LLM::Tool) do
        name "system"
        description "run shell commands"
      end
    end

    before do
      ctx.messages << LLM::Message.new("assistant", nil, {
        tools: [tool],
        tool_calls: [
          {id: "call_1", type: "function", function: {name: "system", arguments: {command: "date"}}}
        ]
      })
      ctx.messages << LLM::Message.new("tool", LLM::Function::Return.new("call_1", "system", {success: true}))
    end

    it "returns tool returns from ctx.returns" do
      expect(ctx.returns.map(&:id)).to eq(["call_1"])
    end

    it "does not include the tool call in ctx.functions" do
      expect(ctx.functions).to be_empty
    end
  end

  context "when configured with a tool instance" do
    let(:provider) { LLM.openai(key: "test") }
    let(:model) { "gpt-5.4" }
    let(:tool) do
      Class.new(LLM::Tool) do
        name "echo"

        def initialize(prefix:)
          @prefix = prefix
        end

        def call(value:)
          {"value" => "#{@prefix}: #{value}"}
        end
      end.new(prefix: "stateful")
    end
    let(:ctx) { LLM::Context.new(provider, model:, tools: [tool]) }

    before do
      ctx.messages << LLM::Message.new("assistant", nil, {
        tools: [tool],
        tool_calls: [
          {id: "call_1", name: "echo", arguments: {"value" => "hello"}}
        ]
      })
    end

    it "resolves and calls the bound tool instance" do
      result = ctx.functions.fetch(0).call
      expect(result.to_h).to eq(
        id: "call_1",
        name: "echo",
        value: {"value" => "stateful: hello"}
      )
    end
  end

  context "when configured with a class-based tool" do
    let(:provider) { LLM.openai(key: "test") }
    let(:model) { "gpt-5.4" }
    let(:tool) do
      Class.new(LLM::Tool) do
        name "system"

        def call(command:)
          {"ok" => command == "date"}
        end
      end
    end
    let(:ctx) { LLM::Context.new(provider, model:, tools: [tool]) }

    before do
      ctx.messages << LLM::Message.new("assistant", nil, {
        tools: [tool],
        tool_calls: [
          {id: "call_1", name: "system", arguments: {"command" => "date"}}
        ]
      })
    end

    it "waits pending tool work with ractor concurrency" do
      expect(ctx.wait(:ractor).map(&:to_h)).to eq([
        {id: "call_1", name: "system", value: {"ok" => true}}
      ])
    end

    it "waits pending tool work with fork concurrency" do
      expect(ctx.wait(:fork).map(&:to_h)).to eq([
        {id: "call_1", name: "system", value: {"ok" => true}}
      ])
    end
  end

  context "#functions?" do
    let(:provider) { LLM.openai(key: "test") }
    let(:model) { "gpt-5.4" }

    context "when unresolved functions exist in message history" do
      let(:tool) do
        Class.new(LLM::Tool) do
          name "system"

          def call(command:)
            {"ok" => command == "date"}
          end
        end
      end
      let(:ctx) { LLM::Context.new(provider, model:, tools: [tool]) }

      before do
        ctx.messages << LLM::Message.new("assistant", nil, {
          tools: [tool],
          tool_calls: [
            {id: "call_1", name: "system", arguments: {"command" => "date"}}
          ]
        })
      end

      it "returns true" do
        expect(ctx.functions?).to eq(true)
      end
    end

    context "when the bound stream queue has pending work" do
      let(:stream) { LLM::Stream.new }
      let(:ctx) { LLM::Context.new(provider, model:, stream:) }
      let(:result) { LLM::Function::Return.new("call_1", "system", {"ok" => true}) }

      before do
        stream.queue << result
      end

      it "returns true" do
        expect(ctx.functions?).to eq(true)
      end
    end

    context "when there is no queued or unresolved tool work" do
      it "returns false" do
        expect(ctx.functions?).to eq(false)
      end
    end
  end

  context "when configured with a transformer" do
    let(:provider) { LLM.openai(key: "test") }
    let(:model) { "gpt-5.4" }
    let(:transformer) do
      Class.new do
        def call(_ctx, prompt, params)
          ["#{prompt} [scrubbed]", params.merge(store: false)]
        end
      end.new
    end
    let(:ctx) { LLM::Context.new(provider, model:, transformer:) }
    let(:responses) { provider.responses }
    let(:response) { double(choices: [LLM::Message.new("assistant", "hello")]) }
    let(:compactor) { instance_double(LLM::Compactor, compact?: false) }
    let(:stream_class) do
      Class.new(LLM::Stream) do
        attr_reader :events

        def initialize
          @events = []
        end

        def on_transform(ctx, transformer)
          @events << [:start, ctx, transformer]
        end

        def on_transform_finish(ctx, transformer)
          @events << [:finish, ctx, transformer]
        end
      end
    end
    let(:stream) { stream_class.new }

    before do
      allow(ctx).to receive(:compactor).and_return(compactor)
    end

    it "rewrites the prompt before talk" do
      allow(provider).to receive(:responses).and_return(responses)
      expect(responses).to receive(:create).with("hello [scrubbed]", hash_including(store: false)).and_return(response)
      ctx.talk("hello")
    end

    it "stores the transformed prompt in message history" do
      allow(provider).to receive(:responses).and_return(responses)
      allow(responses).to receive(:create).and_return(response)
      ctx.talk("hello")
      expect(ctx.messages.first.content).to eq("hello [scrubbed]")
    end

    it "rewrites the prompt before talk in responses mode" do
      responses = double
      ctx = LLM::Context.new(provider, model:, transformer:, mode: :responses)
      allow(ctx).to receive(:compactor).and_return(compactor)
      allow(provider).to receive(:responses).and_return(responses)
      expect(responses).to receive(:create).with("hello [scrubbed]", hash_including(store: false)).and_return(response)
      ctx.talk("hello")
    end

    it "notifies the stream when transform starts" do
      allow(provider).to receive(:responses).and_return(responses)
      allow(responses).to receive(:create).and_return(response)
      ctx.talk("hello", stream:)
      expect(stream.events.first).to eq([:start, ctx, transformer])
    end

    it "notifies the stream when transform finishes" do
      allow(provider).to receive(:responses).and_return(responses)
      allow(responses).to receive(:create).and_return(response)
      ctx.talk("hello", stream:)
      expect(stream.events.last).to eq([:finish, ctx, transformer])
    end
  end

  context "#spawn" do
    let(:provider) { LLM.openai(key: "test") }
    let(:model) { "gpt-5.4" }
    let(:tool) do
      Class.new(LLM::Tool) do
        name "system"

        def call(command:)
          {"ok" => command == "date"}
        end
      end.function.tap do |fn|
        fn.id = "call_1"
        fn.arguments = {"command" => "date"}
      end
    end

    it "spawns the function when no guard blocks it" do
      task = ctx.spawn(tool, :thread)
      expect(task.wait.to_h).to eq(
        id: "call_1",
        name: "system",
        value: {"ok" => true}
      )
    end

    it "returns a guarded tool error when the guard blocks it" do
      ctx.guard = Class.new do
        def call(_ctx)
          "stop"
        end
      end.new
      expect(ctx.spawn(tool, :thread).to_h).to eq(
        id: "call_1",
        name: "system",
        value: {error: true, type: LLM::GuardError.name, message: "stop"}
      )
    end
  end

  context "#usage" do
    let(:provider) { LLM.openai(key: "test") }
    let(:model) { "gpt-5.4" }

    it "zero-fills missing token fields" do
      ctx.messages << LLM::Message.new("assistant", "hello", usage: LLM::Object.from(input_tokens: 3))
      expect(ctx.usage.input_tokens).to eq(3)
      expect(ctx.usage.output_tokens).to eq(0)
      expect(ctx.usage.reasoning_tokens).to eq(0)
      expect(ctx.usage.input_audio_tokens).to eq(0)
      expect(ctx.usage.output_audio_tokens).to eq(0)
      expect(ctx.usage.input_image_tokens).to eq(0)
      expect(ctx.usage.cache_write_tokens).to eq(0)
      expect(ctx.usage.total_tokens).to eq(0)
    end

    it "restores persisted compaction state" do
      ctx.restore(data: {"compacted" => true, "messages" => []})
      expect(ctx.compacted?).to eq(true)
    end
  end

  context "when configured with a stream that supports wait" do
    let(:provider) { LLM.openai(key: "test") }
    let(:model) { "gpt-5.4" }
    let(:stream) { LLM::Stream.new }
    let(:ctx) { LLM::Context.new(provider, model:, stream:) }
    let(:per_call_stream) { LLM::Stream.new }
    let(:responses) { provider.responses }
    let(:response) { double(choices: [LLM::Message.new("assistant", "hello", model:)]) }
    let(:guard) do
      Class.new do
        def call(_ctx)
          "stop"
        end
      end.new
    end
    let(:tool) do
      Class.new(LLM::Tool) do
        name "system"

        def call(command:)
          {"ok" => command == "date"}
        end
      end
    end

    it "forwards #wait to the configured stream when the queue has work" do
      stream.queue << LLM::Function::Return.new("call_1", "system", {"ok" => true})
      expect(ctx.wait(:thread)).to eq([LLM::Function::Return.new("call_1", "system", {"ok" => true})])
    end

    it "forwards #wait(:call) to the configured stream when the queue has work" do
      stream.queue << LLM::Function::Return.new("call_1", "system", {"ok" => true})
      expect(ctx.wait(:call)).to eq([LLM::Function::Return.new("call_1", "system", {"ok" => true})])
    end

    it "waits queued stream work even when a guard is configured" do
      ctx.guard = guard
      stream.queue << LLM::Function::Return.new("call_1", "system", {"ok" => true})
      expect(ctx.wait(:thread)).to eq([LLM::Function::Return.new("call_1", "system", {"ok" => true})])
    end

    it "falls back to pending functions when the queue is empty" do
      pending = [].extend(LLM::Function::Array)
      expect(ctx).to receive(:functions).and_return(pending)
      expect(pending).to receive(:spawn).with(:thread).and_return(LLM::Function::ThreadGroup.new([]))
      expect(ctx.wait(:thread)).to eq([])
    end

    it "flows through pending function spawn groups for #wait(:call)" do
      pending = [].extend(LLM::Function::Array)
      expect(ctx).to receive(:functions).and_return(pending)
      expect(pending).to receive(:spawn).with(:call).and_return(LLM::Function::CallGroup.new([]))
      expect(ctx.wait(:call)).to eq([])
    end

    context "when given a per-call stream" do
      let(:ctx) { LLM::Context.new(provider, model:, stream:) }
      let(:result) { LLM::Function::Return.new("call_1", "system", {"ok" => true}) }

      before do
        allow(ctx).to receive(:compactor).and_return(instance_double(LLM::Compactor, compact?: false))
        allow(provider).to receive(:responses).and_return(responses)
        allow(responses).to receive(:create).and_return(response)
        ctx.talk("hello", stream: per_call_stream)
        per_call_stream.queue << result
      end

      it "waits queued stream work" do
        expect(ctx.wait(:thread)).to eq([result])
      end

      it "waits queued stream work with :call" do
        expect(ctx.wait(:call)).to eq([result])
      end

      it "clears the per-call stream after wait" do
        expect(ctx.instance_variable_get(:@stream)).to eq(per_call_stream)
        ctx.wait(:thread)
        expect(ctx.instance_variable_get(:@stream)).to be_nil
      end
    end

    context "with a guard that wants to stop execution" do
      let(:guard) do
        Class.new do
          def call(_ctx)
            "stop"
          end
        end.new
      end

      it "returns guarded results before spawning pending functions" do
        ctx.guard = guard
        ctx.messages << LLM::Message.new("assistant", nil, {
          tools: [tool],
          tool_calls: [
            {id: "call_1", name: "system", arguments: {"command" => "date"}}
          ]
        })
        pending = ctx.functions
        expect(pending).not_to receive(:spawn)
        allow(ctx).to receive(:functions).and_return(pending)
        expect(ctx.wait(:thread).map(&:value)).to eq([{error: true, type: LLM::GuardError.name, message: "stop"}])
      end
    end
  end

  context "#interrupt!" do
    let(:provider) { LLM.openai(key: "test") }
    let(:model) { "gpt-5.4" }
    let(:responses) { provider.responses }

    it "forwards to the provider" do
      owner = Fiber.new {}
      ctx.instance_variable_set(:@owner, owner)
      expect(provider).to receive(:interrupt!).with(owner).and_return(nil)
      expect(ctx.interrupt!).to be_nil
    end

    it "tracks the executing fiber as the interrupt owner" do
      owner = Fiber.new do
        allow(provider).to receive(:responses).and_return(responses)
        allow(responses).to receive(:create).and_return(double(choices: [LLM::Message.new("assistant", "hello")]))
        ctx.talk("hello")
        expect(provider).to receive(:interrupt!).with(Fiber.current).and_return(nil)
        expect(ctx.interrupt!).to be_nil
      end
      owner.resume
    end

    context "when queued tool work is running through a stream" do
      let(:stream) { LLM::Stream.new }
      let(:ctx) { LLM::Context.new(provider, model:, stream:) }
      let(:tool) do
        Class.new(LLM::Tool) do
          attr_reader :interrupted

          name "echo"
          description "echoes a value"

          def call(value:)
            sleep 0.01 until @interrupted
            {value:}
          end

          def on_interrupt
            @interrupted = true
          end
        end.new
      end

      it "interrupts the queued tool" do
        task = tool.function.tap { _1.arguments = {value: "hello"} }.spawn(:thread)
        stream.queue << task
        expect(provider).to receive(:interrupt!).with(nil).ordered.and_return(nil)
        expect(ctx.interrupt!).to be_nil
        expect(tool.interrupted).to eq(true)
        expect(task.wait.value).to eq({value: "hello"})
      end
    end

    context "when waiting on running tool work directly" do
      let(:stream) { LLM::Stream.new }
      let(:task_class) do
        Class.new do
          attr_reader :interrupted

          def interrupt!
            @interrupted = true
          end
        end
      end
      let(:task) { task_class.new }

      before do
        ctx.instance_variable_set(:@queue, stream.queue << task)
        allow(provider).to receive(:interrupt!).with(nil).and_return(nil)
        ctx.interrupt!
      end

      it "interrupts the provider request" do
        expect(provider).to have_received(:interrupt!).with(nil)
      end

      it "interrupts the active queue task" do
        expect(task.interrupted).to eq(true)
      end
    end

    context "when pending tool calls have no returns yet" do
      let(:tool) do
        Class.new(LLM::Tool) do
          name "echo"

          def call(value:)
            {value:}
          end
        end
      end

      before do
        fn = tool.function
        fn.id = "call_1"
        fn.arguments = {value: "hello"}
        ctx.messages << LLM::Message.new(
          "assistant",
          nil,
          tool_calls: [LLM::Object.from(id: fn.id, name: fn.name, arguments: LLM.json.dump(fn.arguments))],
          original_tool_calls: [{id: fn.id, type: "function", function: {name: fn.name, arguments: LLM.json.dump(fn.arguments)}}],
          tools: [tool]
        )
      end

      it "appends cancellation tool returns" do
        expect(provider).to receive(:interrupt!).with(nil).ordered.and_return(nil)
        expect(ctx.interrupt!).to be_nil
        expect(ctx.messages.last.role).to eq(provider.tool_role.to_s)
        expect(ctx.messages.last.content).to all(be_a(LLM::Function::Return))
        expect(ctx.messages.last.content.map(&:id)).to eq(["call_1"])
        expect(ctx.messages.last.content.map(&:value)).to eq([{cancelled: true, reason: "function call cancelled"}])
      end
    end
  end

  context "#talk" do
    let(:provider) { LLM.openai(key: "test") }
    let(:model) { "gpt-5.4" }
    let(:responses) { provider.responses }
    let(:response) { double(choices: [LLM::Message.new("assistant", "hello")]) }
    let(:compactor) { instance_double(LLM::Compactor, compact?: true, compact!: nil) }

    it "compacts before sending a completions request" do
      allow(ctx).to receive(:compactor).and_return(compactor)
      expect(compactor).to receive(:compact?).with("hello").ordered.and_return(true)
      expect(compactor).to receive(:compact!).with("hello").ordered.and_return(nil)
      allow(provider).to receive(:responses).and_return(responses)
      expect(responses).to receive(:create).ordered.and_return(response)
      ctx.talk("hello")
    end

    it "binds the current context onto the stream" do
      stream = LLM::Stream.new
      ctx = described_class.new(provider, model:, stream:)
      allow(ctx).to receive(:compactor).and_return(instance_double(LLM::Compactor, compact?: false))
      allow(provider).to receive(:responses).and_return(responses)
      expect(responses).to receive(:create).ordered.and_return(response)
      ctx.talk("hello")
      expect(stream.ctx).to eq(ctx)
    end

    context "when given tool returns" do
      let(:compactor) { instance_double(LLM::Compactor, compact?: false) }
      let(:tool) do
        Class.new(LLM::Tool) do
          name "system"
          description "run shell commands"
        end
      end
      let(:result) { LLM::Function::Return.new("call_1", "system", {ok: true}) }

      before do
        ctx.messages << LLM::Message.new("assistant", nil, {
          tools: [tool],
          tool_calls: [
            {id: "call_1", type: "function", function: {name: "system", arguments: {command: "date"}}}
          ]
        })
      end

      it "does not compact before sending tool returns" do
        allow(ctx).to receive(:compactor).and_return(compactor)
        expect(compactor).to receive(:compact?).with([result]).ordered.and_return(false)
        allow(provider).to receive(:responses).and_return(responses)
        expect(responses).to receive(:create).ordered.and_return(response)
        ctx.talk([result])
      end
    end
  end

  context "#compactor" do
    let(:provider) { LLM.openai(key: "test") }
    let(:model) { "gpt-5.4" }
    let(:responses) { provider.responses }
    let(:compactor_options) { {message_threshold: 2, retention_window: 1} }
    let(:ctx) { LLM::Context.new(provider, model:, compactor: compactor_options) }
    let(:summary_text) { "Summary of the earlier conversation" }
    let(:response) { LLM::Object.from(content: summary_text, choices: [LLM::Message.new("assistant", "hello")]) }
    let(:tool) do
      Class.new(LLM::Tool) do
        name "system"
        description "run shell commands"
      end
    end

    it "returns an llm compactor" do
      expect(ctx.compactor).to be_a(LLM::Compactor)
    end

    it "allows assigning compactor config" do
      ctx.compactor = {message_threshold: 4, retention_window: 2}
      expect(ctx.compactor).to be_a(LLM::Compactor)
      expect(ctx.compactor.config).to include(message_threshold: 4, retention_window: 2)
    end

    it "allows assigning an llm compactor" do
      compactor = LLM::Compactor.new(ctx, message_threshold: 4, retention_window: 2)
      ctx.compactor = compactor
      expect(ctx.compactor).to equal(compactor)
    end

    it "does not enable token threshold by default" do
      expect(ctx.compactor.config[:token_threshold]).to be_nil
    end

    context "#compact?" do
      context "when non-system messages exceed the threshold" do
        before do
          ctx.messages << LLM::Message.new("system", "You are helpful")
          ctx.messages << LLM::Message.new("user", "one")
          ctx.messages << LLM::Message.new("assistant", "two")
          ctx.messages << LLM::Message.new("user", "three")
        end

        it { expect(ctx.compactor).to be_compactable }
      end

      context "when token threshold is configured" do
        let(:compactor_options) { {token_threshold: 10, retention_window: 1} }

        before do
          ctx.messages << LLM::Message.new("system", "You are helpful")
          ctx.messages << LLM::Message.new("user", "one")
          allow(ctx).to receive(:usage).and_return(LLM::Object.from(total_tokens: 50))
        end

        it { expect(ctx.compactor).to be_compactable }
      end

      context "when token threshold is configured as a percentage" do
        let(:compactor_options) { {token_threshold: "90%", retention_window: 1} }

        before do
          ctx.messages << LLM::Message.new("system", "You are helpful")
          ctx.messages << LLM::Message.new("user", "one")
          allow(ctx).to receive(:context_window).and_return(100)
          allow(ctx).to receive(:usage).and_return(LLM::Object.from(total_tokens: 95))
        end

        it { expect(ctx.compactor).to be_compactable }
      end

      context "when token threshold is configured as a percentage and the context window is unknown" do
        let(:compactor_options) { {token_threshold: "90%", retention_window: 1} }

        before do
          ctx.messages << LLM::Message.new("system", "You are helpful")
          ctx.messages << LLM::Message.new("user", "one")
          allow(ctx).to receive(:context_window).and_return(0)
          allow(ctx).to receive(:usage).and_return(LLM::Object.from(total_tokens: 95))
        end

        it { expect(ctx.compactor).not_to be_compactable }
      end

      context "during a pending tool lifecycle" do
        let(:result) { LLM::Function::Return.new("call_1", "system", {ok: true}) }

        before do
          ctx.messages << LLM::Message.new("assistant", nil, {
            tools: [tool],
            tool_calls: [
              {id: "call_1", type: "function", function: {name: "system", arguments: {command: "date"}}}
            ]
          })
        end

        it { expect(ctx.compactor).not_to be_compactable([result]) }
      end

      context "when message threshold is disabled" do
        let(:compactor_options) { {token_threshold: 10, retention_window: 1} }

        before do
          ctx.messages << LLM::Message.new("system", "You are helpful")
          ctx.messages << LLM::Message.new("user", "one")
          ctx.messages << LLM::Message.new("assistant", "two")
          ctx.messages << LLM::Message.new("user", "three")
          allow(ctx).to receive(:usage).and_return(LLM::Object.from(total_tokens: 5))
        end

        it { expect(ctx.compactor).not_to be_compactable }
      end

      context "when token threshold is disabled" do
        let(:compactor_options) { {message_threshold: 10, retention_window: 1} }

        before do
          ctx.messages << LLM::Message.new("system", "You are helpful")
          ctx.messages << LLM::Message.new("user", "one")
          allow(ctx).to receive(:usage).and_return(LLM::Object.from(total_tokens: 50_000_000))
        end

        it { expect(ctx.compactor).not_to be_compactable }
      end

      context "when no thresholds are configured" do
        let(:compactor_options) { {retention_window: 1} }

        before do
          ctx.messages << LLM::Message.new("system", "You are helpful")
          ctx.messages << LLM::Message.new("user", "one")
          ctx.messages << LLM::Message.new("assistant", "two")
          ctx.messages << LLM::Message.new("user", "three")
          allow(ctx).to receive(:usage).and_return(LLM::Object.from(total_tokens: 50_000_000))
        end

        it { expect(ctx.compactor).not_to be_compactable }
      end
    end

    context "#compact!" do
      before do
        allow(provider).to receive(:complete).and_return(response)
        allow(provider).to receive(:responses).and_return(responses)
        allow(responses).to receive(:create).and_return(response)
      end

      context "when given a stream" do
        let(:stream) do
          Class.new(LLM::Stream) do
            attr_reader :events

            def initialize
              @events = []
            end

            def on_compaction(ctx, compactor)
              @events << [:start, ctx, compactor]
            end

            def on_compaction_finish(ctx, compactor)
              @events << [:finish, ctx, compactor]
            end
          end.new
        end
        let(:ctx) { LLM::Context.new(provider, model:, stream:, compactor: compactor_options) }

        before do
          ctx.messages << LLM::Message.new("system", "You are helpful")
          ctx.messages << LLM::Message.new("user", "first")
          ctx.messages << LLM::Message.new("assistant", "second")
          ctx.messages << LLM::Message.new("user", "third")
        end

        it "emits compaction lifecycle callbacks" do
          ctx.compactor.compact!
          expect(stream.events).to eq([
            [:start, ctx, ctx.compactor],
            [:finish, ctx, ctx.compactor]
          ])
        end
      end

      context "with ordinary messages" do
        let(:summary) { ctx.compactor.compact! }
        let(:compacted_messages) { summary ? ctx.messages.to_a : [] }

        before do
          ctx.messages << LLM::Message.new("system", "You are helpful")
          ctx.messages << LLM::Message.new("user", "first")
          ctx.messages << LLM::Message.new("assistant", "second")
          ctx.messages << LLM::Message.new("user", "third")
        end

        it "marks the summary as a compaction message" do
          expect(summary).to be_compaction
        end

        it "returns the summary message" do
          expect(summary).to eq(
            LLM::Message.new("user", "[Previous conversation summary]\n\n#{summary_text}", {compaction: true})
          )
        end

        it "replaces older messages with the summary" do
          expect(compacted_messages).to eq([
            LLM::Message.new("system", "You are helpful"),
            summary,
            LLM::Message.new("user", "third")
          ])
        end

        it "keeps the compaction flag in the message history" do
          expect(compacted_messages[1]).to be_compaction
        end

        it "marks the context as compacted" do
          ctx.compactor.compact!
          expect(ctx.compacted?).to eq(true)
        end
      end

      context "after compaction" do
        before do
          ctx.messages << LLM::Message.new("system", "You are helpful")
          ctx.messages << LLM::Message.new("user", "first")
          ctx.messages << LLM::Message.new("assistant", "second")
          ctx.messages << LLM::Message.new("user", "third")
          ctx.compactor.compact!
        end

        it "clears the compacted state after the next successful talk" do
          ctx.talk("hello")
          expect(ctx.compacted?).to eq(false)
        end
      end

      context "when thresholds are disabled" do
        let(:compactor_options) { {message_threshold: nil, token_threshold: nil, retention_window: 1} }
        let(:summary) { ctx.compactor.compact! }

        before do
          ctx.messages << LLM::Message.new("system", "You are helpful")
          ctx.messages << LLM::Message.new("user", "first")
          ctx.messages << LLM::Message.new("assistant", "second")
          ctx.messages << LLM::Message.new("user", "third")
        end

        it "still allows forced manual compaction" do
          expect(summary).to eq(
            LLM::Message.new("user", "[Previous conversation summary]\n\n#{summary_text}", {compaction: true})
          )
        end
      end

      context "during a pending tool lifecycle" do
        let(:compactor_options) { {message_threshold: nil, token_threshold: nil, retention_window: 1} }

        before do
          allow(ctx).to receive(:functions).and_return([tool.function].extend(LLM::Function::Array))
          ctx.messages << LLM::Message.new("user", "third")
        end

        it "does not force compaction" do
          expect(ctx.compactor.compact!).to be_nil
        end
      end

      context "when the retained window would begin on a tool return" do
        let(:compactor_options) { {message_threshold: 2, retention_window: 2} }

        before do
          ctx.messages << LLM::Message.new("system", "You are helpful")
          ctx.messages << LLM::Message.new("user", "first")
          ctx.messages << LLM::Message.new("assistant", nil, {
            tools: [tool],
            tool_calls: [
              {id: "call_1", type: "function", function: {name: "system", arguments: {command: "date"}}}
            ]
          })
          ctx.messages << LLM::Message.new("tool", LLM::Function::Return.new("call_1", "system", {ok: true}))
          ctx.messages << LLM::Message.new("assistant", "done")
        end

        it "keeps the preceding assistant tool call too" do
          summary = ctx.compactor.compact!

          expect(ctx.messages.to_a.map(&:role)).to eq(["system", "user", "assistant", "tool", "assistant"])
          expect(ctx.messages[1]).to eq(summary)
          expect(ctx.messages[2]).to be_tool_call
          expect(ctx.messages[3]).to be_tool_return
          expect(ctx.messages[4].content).to eq("done")
        end
      end
    end
  end
end
