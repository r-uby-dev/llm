# frozen_string_literal: true

require "setup"

RSpec.describe LLM::Stream do
  let(:stream) { described_class.new }
  let(:ctx) { LLM::Context.new(LLM.openai(key: "test"), model: "gpt-5.4") }
  let(:compactor) { LLM::Compactor.new(ctx) }
  let(:filter) { LLM::MessageFilter::Null.new(ctx) }

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

  describe "#on_content" do
    it "returns nil" do
      expect(stream.on_content("hello")).to be_nil
    end
  end

  describe "#<<" do
    it "aliases #on_content" do
      expect(stream << "hello").to be_nil
    end
  end

  describe "#on_reasoning_content" do
    it "returns nil" do
      expect(stream.on_reasoning_content("think")).to be_nil
    end
  end

  describe "#on_tool_call" do
    it "returns nil" do
      expect(stream.on_tool_call(tool)).to be_nil
    end
  end

  describe "#on_tool_return" do
    it "returns nil" do
      expect(stream.on_tool_return(tool, tool.unavailable)).to be_nil
    end
  end

  describe "#on_compaction" do
    it "returns nil" do
      expect(stream.on_compaction(compactor)).to be_nil
    end
  end

  describe "#on_filter" do
    it "returns nil" do
      expect(stream.on_filter(filter)).to be_nil
    end
  end

  describe "#on_filter_finish" do
    it "returns nil" do
      expect(stream.on_filter_finish(filter)).to be_nil
    end
  end

  describe "#on_compaction_finish" do
    it "returns nil" do
      expect(stream.on_compaction_finish(compactor)).to be_nil
    end
  end

  describe "LLM::Function#unavailable" do
    it "returns an in-band error" do
      expect(tool.unavailable.to_h).to eq(
        id: "call_1", name: "system",
        value: {error: true, type: "LLM::NoSuchToolError", message: "tool not found"}
      )
    end

    it "marks the return as an error" do
      expect(tool.unavailable).to be_error
    end
  end

  describe LLM::Function::Return, "#error?" do
    it "returns true for automatic error returns" do
      result = tool.unavailable
      expect(result.error?).to be(true)
    end

    it "returns false for successful returns" do
      result = LLM::Function::Return.new("call_1", "system", {"ok" => true})
      expect(result.error?).to be(false)
    end
  end

  describe "#queue" do
    subject(:queue) { stream.queue }

    it "returns a lazy queue" do
      expect(queue).to be_a(LLM::Stream::Queue)
      expect(queue).to equal(stream.queue)
    end
  end

  describe "#wait" do
    before do
      stream.queue << tool.unavailable
    end

    it "forwards to the queue" do
      expect(stream.wait(:thread).map(&:to_h)).to eq(
        [{id: "call_1", name: "system", value: {error: true, type: "LLM::NoSuchToolError", message: "tool not found"}}]
      )
    end
  end

  context "when a subclass overrides callbacks" do
    let(:stream) do
      Class.new(described_class) do
        attr_reader :content, :reasoning_content, :calls, :returns, :compaction_events, :filter_events

        def initialize
          @content = +""
          @reasoning_content = +""
          @calls = []
          @returns = []
          @compaction_events = []
          @filter_events = []
        end

        def on_content(value)
          @content << value
        end

        def on_reasoning_content(value)
          @reasoning_content << value
        end

        def on_tool_call(fn)
          @calls << fn
        end

        def on_tool_return(fn, result)
          @returns << [fn, result]
        end

        def on_filter(filter)
          @filter_events << [:start, filter]
        end

        def on_filter_finish(filter)
          @filter_events << [:finish, filter]
        end

        def on_compaction(ctx, compactor)
          @compaction_events << [:start, ctx, compactor]
        end

        def on_compaction_finish(ctx, compactor)
          @compaction_events << [:finish, ctx, compactor]
        end
      end.new
    end

    it "handles streamed content" do
      stream.on_content("hello")
      expect(stream.content).to eq("hello")
    end

    it "handles reasoning content" do
      stream.on_reasoning_content("think")
      expect(stream.reasoning_content).to eq("think")
    end

    it "handles tool calls" do
      stream.on_tool_call(tool)
      expect(stream.calls).to eq([tool])
    end

    it "handles finished tools" do
      result = tool.unavailable
      stream.on_tool_return(tool, result)
      expect(stream.returns).to eq([[tool, result]])
    end

    it "handles filtering start" do
      stream.on_filter(filter)
      expect(stream.filter_events).to eq([[:start, filter]])
    end

    it "handles filtering finish" do
      stream.on_filter_finish(filter)
      expect(stream.filter_events).to eq([[:finish, filter]])
    end

    it "handles compaction start" do
      stream.on_compaction(ctx, compactor)
      expect(stream.compaction_events).to eq([[:start, ctx, compactor]])
    end

    it "handles compaction finish" do
      stream.on_compaction_finish(ctx, compactor)
      expect(stream.compaction_events).to eq([[:finish, ctx, compactor]])
    end
  end

  context "when using the queue" do
    describe "#wait" do
      context "when given queued function returns" do
        before do
          stream.queue << tool.unavailable
        end

        it "returns the queued values" do
          expect(stream.wait(:thread).map(&:to_h)).to eq(
            [{id: "call_1", name: "system", value: {error: true, type: "LLM::NoSuchToolError", message: "tool not found"}}]
          )
        end
      end

      context "when given spawned work" do
        it "waits for the spawned work" do
          stream.queue << tool.task(:thread)
          expect(stream.wait(:thread).map(&:to_h)).to eq(
            [{id: "call_1", name: "system", value: {"ok" => true}}]
          )
        end

        context "when tracking tool return callbacks" do
          let(:stream) do
            Class.new(described_class) do
              attr_reader :events

              def initialize
                @events = []
              end

              def on_tool_return(fn, result)
                @events << [fn, result]
              end
            end.new
          end

          it "emits on_tool_return" do
            stream.queue << tool.task(:thread)
            returns = stream.wait(:thread)
            expect(stream.events).to eq([[tool, returns.fetch(0)]])
          end
        end
      end

      context "when given ractor work" do
        before do
          stream.queue << tool.task(:ractor)
        end

        it "waits for the spawned work" do
          expect(stream.wait(:ractor).map(&:to_h)).to eq(
            [{id: "call_1", name: "system", value: {"ok" => true}}]
          )
        end
      end

      context "when given mixed spawned work" do
        subject(:returns) { stream.wait([:thread, :ractor]).map(&:to_h) }

        let(:other_tool) do
          tool_class.function.dup.tap do |fn|
            fn.id = "call_2"
            fn.arguments = {"command" => "date"}
          end
        end

        before do
          stream.queue << tool.task(:thread)
          stream.queue << other_tool.task(:ractor)
        end

        it "waits for all matching task types" do
          expect(returns).to eq(
            [
              {id: "call_1", name: "system", value: {"ok" => true}},
              {id: "call_2", name: "system", value: {"ok" => true}}
            ]
          )
        end

        context "when tracking tool return callbacks" do
          let(:stream) do
            Class.new(described_class) do
              attr_reader :events

              def initialize
                @events = []
              end

              def on_tool_return(fn, result)
                @events << [fn.id, result.id]
              end
            end.new
          end
          let(:third_tool) do
            tool_class.function.dup.tap do |fn|
              fn.id = "call_3"
              fn.arguments = {"command" => "date"}
            end
          end
          let(:expected_ids) { %w[call_1 call_2 call_3] }
          let(:result_ids) { stream.wait([:thread, :ractor]).map(&:id) }

          before do
            stream.queue << third_tool.task(:thread)
            result_ids
          end

          it "preserves enqueue order across mixed task groups" do
            expect(result_ids).to eq(expected_ids)
          end

          it "emits a tool return callback for each tool" do
            expect(stream.events.map(&:first)).to contain_exactly(*expected_ids)
          end

          it "emits each tool return callback once" do
            expect(stream.events.size).to eq(expected_ids.size)
          end
        end
      end
    end
  end
end
