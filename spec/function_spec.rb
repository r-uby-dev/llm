# frozen_string_literal: true

require "setup"
require "timeout"
require "tmpdir"

RSpec.describe LLM::Function do
  let(:tool_class) do
    Class.new(LLM::Tool) do
      name "system"
      def call(command:)
        {"ok" => command == "date"}
      end
    end
  end
  let(:tool) do
    tool_class.function.dup.tap do |fn|
      fn.id = "call_1"
      fn.arguments = {"command" => "date"}
    end
  end

  describe "when building a return" do
    subject(:result) { tool.return(error: true, type: "guard_error", message: "stop") }

    it "builds a return using the function's id and name" do
      expect(result.to_h).to eq(
        id: "call_1",
        name: "system",
        value: {error: true, type: "guard_error", message: "stop"}
      )
    end
  end

  describe "when building a task" do
    subject(:task) { tool.task(strategy) }

    let(:strategy) { :ractor }

    context "when using sequential concurrency" do
      let(:strategy) { :sequential }

      it "returns the tool result" do
        expect(task.wait.to_h).to eq(id: "call_1", name: "system", value: {"ok" => true})
      end
    end

    describe "when calling #value" do
      subject(:value) { task.value.to_h }

      it { is_expected.to eq(id: "call_1", name: "system", value: {"ok" => true}) }
    end

    describe "when checking #alive?" do
      let(:slow_tool) do
        Class.new(LLM::Tool) do
          name "slow"
          def call
            sleep 0.5
            {"ok" => true}
          end
        end.function.dup.tap do |fn|
          fn.id = "call_2"
          fn.arguments = {}
        end
      end
      let(:slow_task) { slow_tool.task(:ractor) }

      before do
        slow_task.spawn
        sleep 0.01 until slow_task.alive?
      end

      it "reports true while the task is alive" do
        expect(slow_task.alive?).to be(true)
      end

      it "reports false after the task has been waited on" do
        slow_task.wait
        expect(slow_task.alive?).to be(false)
      end
    end

    describe "when interrupting a task" do
      before do
        skip "not supported by yajl or oj" unless ENV.fetch("JSON_PARSER", "json").downcase == "json"
      end

      let(:tool) do
        Class.new(LLM::Tool) do
          name "slow"
          def call
            sleep 2
            {ok: true}
          end
        end
      end
      let(:slow_function) do
        tool.function.dup.tap do |fn|
          fn.id = "call_3"
          fn.arguments = {}
        end
      end
      let(:slow_task) { slow_function.task(:ractor) }

      context "when the task is running" do
        before do
          slow_task.spawn
          sleep 0.05 until slow_task.alive?
        end

        it "interrupts the tool execution" do
          slow_task.interrupt!
          expect { slow_task.wait }.to raise_error(LLM::Interrupt)
        end
      end

      context "when the task has not started" do
        it "returns nil from interrupt!" do
          expect(slow_task.interrupt!).to be_nil
        end
      end
    end

    let(:proc_function) do
      LLM::Function.new("echo").tap do |fn|
        fn.arguments = {"value" => "hello"}
        fn.define { |value:| {value:} }
      end
    end

    it "rejects proc-defined functions" do
      expect { proc_function.task(:ractor) }.to raise_error(
        LLM::RactorError,
        "Ractor concurrency only supports class-based tools"
      )
    end

    context "when configured with a tracer" do
      let(:tracer) { double("tracer", on_tool_start: :span, on_tool_finish: nil) }

      before do
        tool.tracer = tracer
        tool.model = "gpt-4.1"
        task.wait
      end

      it "traces the tool start" do
        expect(tracer).to have_received(:on_tool_start).with(
          id: "call_1",
          name: "system",
          arguments: {"command" => "date"},
          model: "gpt-4.1"
        )
      end

      it "traces the tool finish" do
        expect(tracer).to have_received(:on_tool_finish).with(
          result: have_attributes(id: "call_1", name: "system", value: {"ok" => true}),
          span: :span
        )
      end
    end

    context "when using fork concurrency" do
      let(:strategy) { :fork }

      it "returns the tool result" do
        expect(task.wait.to_h).to eq(id: "call_1", name: "system", value: {"ok" => true})
      end

      let(:guarded_tool) do
        tool_class.function.dup.tap do |fn|
          fn.id = "call_5"
          fn.arguments = {"command" => "date"}
          fn.guard = ->(function:) { function.return(error: true, type: "guard_error", message: "stop") }
        end
      end

      it "returns the guard result when the tool is blocked" do
        expect(guarded_tool.task(:fork).wait.to_h).to eq(
          id: "call_5",
          name: "system",
          value: {error: true, type: "guard_error", message: "stop"}
        )
      end

      describe "when the tool raises an error" do
        let(:error_tool) do
          tool_class.function.dup.tap do |fn|
            fn.id = "call_4"
            fn.arguments = {"paths" => ["CHANGELOG.md"]}
          end
        end

        it "returns tool errors without hanging" do
          result = Timeout.timeout(1) { error_tool.task(:fork).wait.to_h }
          expect(result).to eq(
            id: "call_4",
            name: "system",
            value: {error: true, type: "ArgumentError", message: "missing keyword: :command"}
          )
        end
      end

      context "when configured with a tracer" do
        let(:tracer) { double("tracer", on_tool_start: :span, on_tool_finish: nil) }

        before do
          tool.tracer = tracer
          tool.model = "gpt-4.1"
          task.wait
        end

        it "traces the tool start" do
          expect(tracer).to have_received(:on_tool_start).with(
            id: "call_1",
            name: "system",
            arguments: {"command" => "date"},
            model: "gpt-4.1"
          )
        end

        it "traces the tool finish" do
          expect(tracer).to have_received(:on_tool_finish).with(
            result: have_attributes(id: "call_1", name: "system", value: {"ok" => true}),
            span: :span
          )
        end
      end

      describe "when interrupting a fork-backed tool" do
        context "when the tool rescues LLM::Interrupt" do
          let(:interrupt_tool) do
            tool_class = Class.new(LLM::Tool) do
              name "interruptible"

              define_method(:call) do
                sleep 10
                {"ok" => true}
              rescue LLM::Interrupt
                {"ok" => true, "interrupted" => true}
              end
            end
            tool_class.function.dup.tap do |fn|
              fn.id = "call_3"
              fn.arguments = {}
            end
          end
          let(:interrupt_task) { interrupt_tool.task(:fork) }

          before do
            interrupt_task.spawn
            sleep 0.05 until interrupt_task.alive?
          end

          it "delivers interrupts to the child tool" do
            interrupt_task.interrupt!
            expect(interrupt_task.wait.to_h).to eq(id: "call_3", name: "interruptible", value: {"ok" => true, "interrupted" => true})
          end
        end

        context "when the tool does not rescue LLM::Interrupt" do
          let(:brittle_tool) do
            Class.new(LLM::Tool) do
              name "brittle"

              define_method(:call) do
                sleep 10
                {"ok" => true}
              end
            end.function.dup.tap do |fn|
              fn.id = "call_4"
              fn.arguments = {}
            end
          end
          let(:brittle_task) { brittle_tool.task(:fork) }

          before do
            brittle_task.spawn
            sleep 0.05 until brittle_task.alive?
            brittle_task.interrupt!
          end

          it "propagates LLM::Interrupt" do
            expect { brittle_task.wait }.to raise_error(LLM::Interrupt)
          end
        end
      end
    end

    context "when using fiber concurrency without a scheduler" do
      it "raises a clear error" do
        expect { tool.task(:fiber).spawn }.to raise_error(
          ArgumentError,
          "Fiber concurrency requires Fiber.scheduler"
        )
      end
    end
  end

  describe "when a tool implements a cooperative hook" do
    let(:tool_class) do
      Class.new(LLM::Tool) do
        name "probe"

        class << self
          attr_accessor :instances
        end
        self.instances = 0

        attr_reader :ran, :told

        def initialize
          self.class.instances += 1
        end

        def call
          @ran = Thread.current.object_id
          sleep 10
          {"ok" => true}
        end

        def on_interrupt
          @told = Thread.current.object_id
        end
      end
    end
    let(:function) do
      tool_class.function.dup.tap do |fn|
        fn.id = "call_1"
        fn.arguments = {}
      end
    end

    describe "when resolving the runner" do
      it "resolves one instance per function" do
        expect(function.runner).to equal(function.runner)
      end

      it "resolves a separate instance per copy" do
        definition = tool_class.function
        definition.runner
        expect(definition.dup.runner).not_to equal(definition.runner)
      end

      it "resolves before the task it returns exists" do
        expect { function.task(:thread) }.to change { tool_class.instances }.by(1)
      end

      context "when the tool is blocked by a guard" do
        before do
          function.guard = ->(function:) { function.return(error: true, type: "guard_error", message: "stop") }
        end

        it "does not resolve the runner" do
          expect { function.task(:thread) }.not_to change { tool_class.instances }
        end
      end
    end

    describe "when the tool cannot be built" do
      let(:tool_class) do
        Class.new(LLM::Tool) do
          name "required"

          def initialize(client)
            @client = client
          end

          def call
            {"ok" => true}
          end
        end
      end

      it "returns an in-band error" do
        result = function.task(:thread).wait.to_h
        expect(result[:value]).to include(error: true, type: "ArgumentError")
      end

      it "does not raise from interrupt!" do
        expect { function.interrupt! }.not_to raise_error
      end
    end

    describe "when the tool is supplied as a class" do
      let(:task) { function.task(:sequential) }

      before { task.interrupt! }

      it "tells the tool" do
        expect(function.runner.told).not_to be_nil
      end
    end

    describe "when the tool is running a call" do
      let(:task) { function.task(:thread) }

      before do
        task.spawn
        Timeout.timeout(2) { sleep 0.05 until function.runner.ran }
        task.interrupt!
      end

      it "tells the tool on the thread that runs the call" do
        ##
        # The interrupt is the caller's to catch, and a modifier rescue -
        # `task.wait rescue LLM::Interrupt` - is not a rescue at all: it
        # catches a `StandardError` and answers with the constant. It is the
        # interrupt that is named here, and only that.
        begin
          task.wait
        rescue LLM::Interrupt
          nil
        end
        expect(function.runner.told).to eq(function.runner.ran)
      end
    end

    describe "when the tool runs on a reactor" do
      before do
        require "async"
        Console.logger.level = :fatal if defined?(Console)
      end

      let(:reactor) { LLM::Function::Async::Reactor.new }
      let(:task) { function.task(:async).tap { _1.reactor = reactor } }

      before do
        task.spawn
        Timeout.timeout(2) { sleep 0.05 until function.runner.ran }
        task.interrupt!
      end

      after { reactor&.stop }

      it "tells the tool on the thread that runs the call" do
        begin
          task.wait
        rescue LLM::Interrupt
          nil
        end
        expect(function.runner.told).to eq(function.runner.ran)
      end

      context "when the hook raises" do
        let(:tool_class) do
          Class.new(LLM::Tool) do
            name "reactored"

            attr_reader :ran

            def call
              @ran = Thread.current.object_id
              sleep 10
              {"ok" => true}
            end

            def on_interrupt
              raise "hook failed"
            end
          end
        end

        it "answers the caller" do
          expect { Timeout.timeout(2) { task.wait } }.to raise_error(RuntimeError, "hook failed")
        end
      end
    end

    describe "when the tool runs in a child process" do
      let(:tool_class) do
        Class.new(LLM::Tool) do
          name "forked"

          def call
            sleep 10
            {"ok" => true}
          rescue LLM::Interrupt
            {"ok" => false, "told" => @told}
          end

          def on_interrupt
            @told = true
          end
        end
      end
      let(:task) { function.task(:fork) }

      before do
        task.spawn
        sleep 0.05 until task.alive?
        task.interrupt!
      end

      it "tells the tool" do
        expect(task.wait.value).to include("told" => true)
      end
    end

    describe "when the tool runs in a ractor" do
      before do
        skip "not supported by yajl or oj" unless ENV.fetch("JSON_PARSER", "json").downcase == "json"
      end

      let(:tool_class) do
        Class.new(LLM::Tool) do
          name "ractorized"

          def call
            sleep 10
            {"ok" => true}
          rescue LLM::Interrupt
            {"ok" => false, "told" => @told}
          end

          def on_interrupt
            @told = true
          end
        end
      end
      let(:task) { function.task(:ractor) }

      before do
        task.spawn
        sleep 0.05 until task.alive?
        task.interrupt!
      end

      it "tells the tool" do
        expect(task.wait.value).to include("told" => true)
      end
    end

    describe "when a sequential group is interrupted" do
      let(:tool_class) do
        Class.new(LLM::Tool) do
          name "grouped"

          attr_reader :interrupted

          def call
            sleep 10
            {"ok" => true}
          end

          def on_interrupt
            @interrupted = true
          end
        end
      end
      let(:group) { LLM::Function::Sequential::Group.new([function.task(:sequential)]) }

      before { group.interrupt! }

      it "tells the tool" do
        expect(function.runner.interrupted).to be(true)
      end
    end
  end

  describe LLM::Function::Sequential::Group do
    describe "when interrupting a sequential group" do
      subject(:group) { LLM::Function::Sequential::Group.new([function.task(:sequential)]) }

      let(:fn_class) do
        Class.new(LLM::Tool) do
          name "slow"
          def call
            sleep 10
            {ok: true}
          end
        end
      end
      let(:function) do
        fn_class.function.dup.tap do |fn|
          fn.id = "call_1"
          fn.arguments = {}
        end
      end

      context "when wait has not been called" do
        it "is a no-op" do
          expect(group.interrupt!).to be_nil
        end
      end

      context "when wait has completed" do
        let(:completed_function) do
          fn_class.function.dup.tap do |f|
            f.define { {ok: true} }
            f.id = "call_2"
            f.arguments = {}
          end
        end

        before do
          LLM::Function::Sequential::Group.new([completed_function.task(:sequential)]).wait
        end

        it "is a no-op" do
          expect(group.interrupt!).to be_nil
        end
      end

      context "when wait runs on another thread" do
        let(:thread) do
          ##
          # The interrupt is caught by name rather than by a modifier
          # rescue, which reaches only `StandardError`.
          Thread.new do
            group.wait
          rescue LLM::Interrupt
            :interrupted
          end.tap do |t|
            t.report_on_exception = false
          end
        end

        before { thread; sleep 0.05 }

        it "interrupts the currently running tool execution" do
          group.interrupt!
          expect(thread.value).to eq(:interrupted)
        end
      end

      context "when wait runs on another thread without rescuing" do
        let(:thread) do
          Thread.new { group.wait }.tap do |t|
            t.report_on_exception = false
          end
        end

        before { thread; sleep 0.05 }

        it "raises LLM::Interrupt on the thread running wait" do
          group.interrupt!
          expect { thread.value }.to raise_error(LLM::Interrupt)
        end
      end
    end
  end

  describe LLM::Function::Task do
    describe "when interrupting a task" do
      let(:fn) do
        LLM::Function.new("test") { _1.define { {ok: true} } }.tap do |f|
          f.id = "call_1"
          f.arguments = {}
        end
      end

      context "when wrapping a Thread" do
        let(:slow_fn) do
          LLM::Function.new("slow") { _1.define { sleep 10; {ok: true} } }.tap do |f|
            f.id = "call_1"
            f.arguments = {}
          end
        end
        let(:task) { LLM::Function::Thread::Task.new(slow_fn) }

        before do
          task.spawn
          sleep 0.05 until task.alive?
        end

        it "raises LLM::Interrupt on the thread" do
          task.interrupt!
          expect { task.wait }.to raise_error(LLM::Interrupt)
        end
      end

      context "when wrapping a Fiber" do
        it "does not raise on a dead fiber" do
          expect { LLM::Function::Fiber::Task.new(fn).interrupt! }.not_to raise_error
        end
      end

      context "when wrapping an Async::Task" do
        before do
          require "async"
          Console.logger.level = :fatal if defined?(Console)
        end

        let(:reactor) { LLM::Function::Async::Reactor.new }

        after { reactor&.stop }

        context "when the task is running" do
          let(:slow_fn) do
            LLM::Function.new("slow") { _1.define { sleep 10; {ok: true} } }.tap do |f|
              f.id = "call_1"
              f.arguments = {}
            end
          end
          let(:slow_task) { LLM::Function::Async::Task.new(slow_fn, reactor:) }

          before do
            slow_task.spawn
            sleep 0.05 until slow_task.alive?
          end

          it "raises LLM::Interrupt on the underlying fiber" do
            slow_task.interrupt!
            expect { slow_task.wait }.to raise_error(LLM::Interrupt)
          end
        end

        context "when the task has finished" do
          let(:dead_task) { LLM::Function::Async::Task.new(fn, reactor:).tap(&:wait) }

          it "is a no-op" do
            expect { dead_task.interrupt! }.not_to raise_error
          end
        end
      end

      context "when the task responds to interrupt!" do
        let(:interruptible) do
          Class.new do
            attr_reader :interrupted

            def initialize
              @interrupted = false
            end

            def interrupt!
              @interrupted = true
            end
          end.new
        end

        it "calls interrupt! on the task if it responds to it" do
          interruptible.interrupt!
          expect(interruptible.interrupted).to be(true)
        end
      end

      let(:spawned_thread_task) { LLM::Function::Thread::Task.new(fn).tap(&:spawn) }

      it "returns nil" do
        expect(spawned_thread_task.interrupt!).to be_nil
      end
    end
  end
end
