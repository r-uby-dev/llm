# frozen_string_literal: true

require "setup"

RSpec.describe LLM::EventStream::Parser do
  let(:provider) { LLM.openai(key: "test") }
  let(:stream) do
    Class.new(LLM::Stream) do
      attr_reader :content

      def initialize
        @content = +""
      end

      def on_content(value)
        @content << value
      end
    end.new
  end
  let(:handler) { LLM::EventHandler.new(provider.class::StreamParser.new(stream)) }
  subject(:parser) do
    described_class.new.tap do |instance|
      instance.register(handler)
    end
  end

  after { parser.free }

  describe "#<<" do
    let(:partial_line) { 'data: {"choices":[{"index":0,"delta":{"content":"He' }
    let(:remaining_lines) do
      <<~DATA
        y"}}]}
        data: {"choices":[{"index":0,"delta":{"content":" there"}}]}
      DATA
    end

    context "when given a partial sse data line without a trailing newline" do
      before { parser << partial_line }

      it "does not emit content to the stream" do
        expect(stream.content).to eq("")
      end

      it "does not build a response body yet" do
        expect(handler.body).to eq({})
      end
    end

    context "when the newline and remaining data arrive later" do
      before do
        parser << partial_line
        parser << remaining_lines
      end

      it "preserves the full streamed content" do
        expect(stream.content).to eq("Hey there")
      end

      it "preserves the full parsed message content" do
        expect(handler.body.dig("choices", 0, "message", "content")).to eq("Hey there")
      end
    end

    context "when given reasoning content" do
      let(:stream) do
        Class.new(LLM::Stream) do
          attr_reader :content, :reasoning_content

          def initialize
            @content = +""
            @reasoning_content = +""
          end

          def on_content(value)
            @content << value
          end

          def on_reasoning_content(value)
            @reasoning_content << value
          end
        end.new
      end

      before do
        parser << %(data: {"choices":[{"index":0,"delta":{"reasoning_content":"Think"}}]}\n)
        parser << %(data: {"choices":[{"index":0,"delta":{"content":"Answer"}}]}\n)
      end

      it "emits assistant content through on_content" do
        expect(stream.content).to eq("Answer")
      end

      it "emits reasoning content through on_reasoning_content" do
        expect(stream.reasoning_content).to eq("Think")
      end

      it "preserves streamed reasoning content in the parsed body" do
        expect(handler.body.dig("choices", 0, "message", "reasoning_content")).to eq("Think")
      end
    end

    context "when given a streamed tool call" do
      let(:system) do
        Class.new(LLM::Tool) do
          name "system"
          description "run shell commands"
        end
      end

      let(:stream) do
        Class.new(LLM::Stream) do
          attr_reader :calls

          def initialize
            @calls = []
          end

          def on_tool_call(fn)
            @calls << fn
          end
        end.new
      end

      before { LLM::Tool.clear_registry! }
      before { system }

      before do
        parser << %(data: {"choices":[{"index":0,"delta":{"tool_calls":[{"index":0,"id":"call_1","type":"function","function":{"name":"system","arguments":"{\\"command\\":\\"date\\"}"}}]}}]}\n)
      end

      context "when given the emitted function" do
        subject(:fn) { stream.calls.fetch(0) }

        it "emits a function through on_tool_call" do
          expect(fn).to be_a(LLM::Function)
        end

        it "preserves the function id" do
          expect(fn.id).to eq("call_1")
        end

        it "preserves the function name" do
          expect(fn.name).to eq("system")
        end

        it "preserves parsed arguments" do
          expect(fn.arguments).to eq({"command" => "date"})
        end
      end
    end

    context "when given an unresolved streamed tool call" do
      let(:stream) do
        Class.new(LLM::Stream) do
          attr_reader :calls

          def initialize
            @calls = []
          end

          def on_tool_call(fn)
            @calls << fn
          end
        end.new
      end

      before { LLM::Tool.clear_registry! }

      before do
        parser << %(data: {"choices":[{"index":0,"delta":{"tool_calls":[{"index":0,"id":"call_2","type":"function","function":{"name":"missing","arguments":"{\\"command\\":\\"date\\"}"}}]}}]}\n)
      end

      it "enqueues an in-band error for an unresolved tool" do
        returns = stream.queue.wait
        expect(returns.size).to eq(1)
        error = returns.first
        expect(error.id).to eq("call_2")
        expect(error.name).to eq("missing")
        expect(error.to_h).to eq(
          id: "call_2", name: "missing",
          value: {error: true, type: "LLM::NoSuchToolError", message: "tool not found"}
        )
      end
    end

    context "when given a streamed Google tool call" do
      let(:provider) { LLM.google(key: "test") }
      let(:system) do
        Class.new(LLM::Tool) do
          name "system"
          description "run shell commands"
        end
      end

      let(:stream) do
        Class.new(LLM::Stream) do
          attr_reader :calls

          def initialize
            @calls = []
          end

          def on_tool_call(fn)
            @calls << fn
          end
        end.new
      end

      before { LLM::Tool.clear_registry! }
      before { system }

      before do
        parser << %(data: {"candidates":[{"content":{"parts":[{"functionCall":{"name":"system","args":{"command":"date"}}}],"role":"model"},"index":0}]}\n)
      end

      it "emits a resolved function through on_tool_call" do
        fn = stream.calls.fetch(0)
        expect(fn).to be_a(LLM::Function)
        expect(fn.id).to start_with("google_")
        expect(fn.name).to eq("system")
        expect(fn.arguments).to eq({"command" => "date"})
      end
    end

    context "when given a streamed Google tool call without thoughtSignature" do
      let(:provider) { LLM.google(key: "test") }
      let(:system) do
        Class.new(LLM::Tool) do
          name "system"
          description "run shell commands"
        end
      end

      let(:stream) do
        Class.new(LLM::Stream) do
          attr_reader :calls

          def initialize
            @calls = []
          end

          def on_tool_call(fn)
            @calls << fn
          end
        end.new
      end

      before { LLM::Tool.clear_registry! }
      before { system }

      before do
        parser << %(data: {"candidates":[{"content":{"parts":[{"functionCall":{"name":"system","args":{"command":"date"}}}],"role":"model"},"index":0}]}\n)
      end

      it "synthesizes a fallback function id" do
        fn = stream.calls.fetch(0)
        expect(fn.id).to eq("google_call_0_0")
      end
    end

    context "when given a streamed Anthropic tool call" do
      let(:provider) { LLM.anthropic(key: "test") }
      let(:system) do
        Class.new(LLM::Tool) do
          name "system"
          description "run shell commands"
        end
      end

      let(:stream) do
        Class.new(LLM::Stream) do
          attr_reader :calls

          def initialize
            @calls = []
          end

          def on_tool_call(fn)
            @calls << fn
          end
        end.new
      end

      before { LLM::Tool.clear_registry! }
      before { system }

      before do
        parser << %(event: content_block_start\ndata: {"type":"content_block_start","index":0,"content_block":{"type":"tool_use","id":"toolu_1","name":"system","input":{}}}\n\n)
        parser << %(event: content_block_delta\ndata: {"type":"content_block_delta","index":0,"delta":{"type":"input_json_delta","partial_json":"{\\"command\\": \\"date\\"}"}}\n\n)
        parser << %(event: content_block_stop\ndata: {"type":"content_block_stop","index":0}\n\n)
      end

      it "emits a resolved function through on_tool_call" do
        fn = stream.calls.fetch(0)
        expect(fn).to be_a(LLM::Function)
        expect(fn.id).to eq("toolu_1")
        expect(fn.name).to eq("system")
        expect(fn.arguments).to eq({"command" => "date"})
      end
    end

    context "when given a streamed OpenAI Responses tool call" do
      let(:handler) { LLM::EventHandler.new(LLM::OpenAI::Responses::StreamParser.new(stream)) }
      let(:system) do
        Class.new(LLM::Tool) do
          name "system"
          description "run shell commands"
        end
      end

      let(:stream) do
        Class.new(LLM::Stream) do
          attr_reader :calls

          def initialize
            @calls = []
          end

          def on_tool_call(fn)
            @calls << fn
          end
        end.new
      end

      before { LLM::Tool.clear_registry! }
      before { system }

      before do
        parser << %(event: response.output_item.added\ndata: {"type":"response.output_item.added","item":{"id":"fc_1","type":"function_call","status":"in_progress","arguments":"","call_id":"call_1","name":"system"},"output_index":0}\n\n)
        parser << %(event: response.function_call_arguments.delta\ndata: {"type":"response.function_call_arguments.delta","delta":"{\\"command\\":\\"date\\"}","item_id":"fc_1","output_index":0}\n\n)
        parser << %(event: response.function_call_arguments.done\ndata: {"type":"response.function_call_arguments.done","arguments":"{\\"command\\":\\"date\\"}","item_id":"fc_1","output_index":0}\n\n)
      end

      it "emits a resolved function through on_tool_call" do
        fn = stream.calls.fetch(0)
        expect(fn).to be_a(LLM::Function)
        expect(fn.id).to eq("call_1")
        expect(fn.name).to eq("system")
        expect(fn.arguments).to eq({"command" => "date"})
      end
    end

    context "when given streamed OpenAI Responses reasoning content" do
      let(:handler) { LLM::EventHandler.new(LLM::OpenAI::Responses::StreamParser.new(stream)) }
      let(:stream) do
        Class.new(LLM::Stream) do
          attr_reader :content, :reasoning_content

          def initialize
            @content = +""
            @reasoning_content = +""
          end

          def on_content(value)
            @content << value
          end

          def on_reasoning_content(value)
            @reasoning_content << value
          end
        end.new
      end

      before do
        parser << %(event: response.output_item.added\ndata: {"type":"response.output_item.added","item":{"id":"rs_1","type":"reasoning","summary":[]},"output_index":0}\n\n)
        parser << %(event: response.reasoning_summary_text.delta\ndata: {"type":"response.reasoning_summary_text.delta","output_index":0,"summary_index":0,"delta":"Think"}\n\n)
        parser << %(event: response.reasoning_summary_text.done\ndata: {"type":"response.reasoning_summary_text.done","output_index":0,"summary_index":0,"text":"Think"}\n\n)
        parser << %(event: response.output_item.added\ndata: {"type":"response.output_item.added","item":{"id":"msg_1","type":"message","content":[]},"output_index":1}\n\n)
        parser << %(event: response.content_part.added\ndata: {"type":"response.content_part.added","output_index":1,"content_index":0,"part":{"type":"output_text","text":""}}\n\n)
        parser << %(event: response.output_text.delta\ndata: {"type":"response.output_text.delta","output_index":1,"content_index":0,"delta":"Answer"}\n\n)
      end

      it "emits assistant content through on_content" do
        expect(stream.content).to eq("Answer")
      end

      it "emits reasoning content through on_reasoning_content" do
        expect(stream.reasoning_content).to eq("Think")
      end

      it "preserves streamed reasoning content in the parsed body" do
        expect(handler.body.dig("output", 0, "summary", 0, "text")).to eq("Think")
      end
    end
  end

  describe "#on" do
    let(:events) { [] }
    subject(:parser) do
      described_class.new.tap do |instance|
        instance.on(:data) { events << it }
      end
    end

    after { parser.free }

    it "still yields event objects to callback subscribers" do
      parser << %(data: {"ok":true}\n)
      event = events.fetch(0)
      expect(event).to be_a(LLM::EventStream::Event)
      expect(event.field).to eq("data")
      expect(event.value).to eq('{"ok":true}')
      expect(event.chunk).to eq(%(data: {"ok":true}\n))
    end
  end
end
