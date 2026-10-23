# frozen_string_literal: true

require "setup"

RSpec.describe LLM::Transport::StreamDecoder do
  let(:parser_class) do
    Class.new do
      attr_reader :chunks

      def initialize
        @chunks = []
      end

      def parse!(chunk)
        @chunks << chunk
      end

      def body
        {"chunks" => @chunks}
      end

      def free
        @chunks.clear
      end
    end
  end

  let(:parser) { parser_class.new }
  subject(:decoder) { described_class.new(parser) }

  after { decoder.free }

  it "decodes sse data events directly into the parser" do
    decoder << %(data: {"ok":true}\n\n)
    decoder << %(data: [DONE]\n\n)
    expect(parser.chunks).to eq([{"ok" => true}])
  end

  it "joins multiline sse data payloads before decoding" do
    decoder << %(event: message\n)
    decoder << %(data: {"ok":\n)
    decoder << %(data: true}\n\n)
    expect(parser.chunks).to eq([{"ok" => true}])
  end

  it "flushes sse events separated with crlf" do
    decoder << "data: {\"ok\":true}\r\n\r\n"
    expect(parser.chunks).to eq([{"ok" => true}])
  end

  it "decodes raw json lines for non-sse streams" do
    decoder << %({"ok":true}\n)
    decoder << %({"value":1}\n)
    expect(parser.chunks).to eq([{"ok" => true}, {"value" => 1}])
  end

  it "waits for a newline before decoding a partial line" do
    decoder << '{"ok":'
    expect(parser.chunks).to eq([])
    decoder << %(true}\n)
    expect(parser.chunks).to eq([{"ok" => true}])
  end

  context "when initialized with a block" do
    let(:chunks) { [] }
    subject(:decoder) { described_class.new { chunks << it } }

    it "yields decoded sse payloads to the block" do
      decoder << %(data: {"ok":true}\n\n)
      expect(chunks).to eq([{"ok" => true}])
    end
  end
end
