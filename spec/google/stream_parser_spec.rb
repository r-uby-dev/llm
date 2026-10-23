# frozen_string_literal: true

require "setup"
require "llm/providers/google"

RSpec.describe LLM::Google::StreamParser do
  let(:stream) do
    Class.new(LLM::Stream) do
      attr_reader :calls

      def initialize
        @calls = []
      end

      def on_content(content)
        nil
      end

      def on_tool_call(fn)
        @calls << fn
      end
    end.new
  end

  let(:parts) { parser.body.dig("candidates", 0, "content", "parts") }

  subject(:parser) { described_class.new(stream) }

  after { parser.free }

  before { LLM::Tool.clear_registry! }
  before { stream.extra[:tracer] = LLM::Tracer::Null.new(provider) }
  before { stream.extra[:model] = "gemini-3.1-flash-lite" }

  let(:provider) { LLM.google(key: "test") }

  def parse!(part)
    parser.parse!({"candidates" => [{"index" => 0, "content" => {"parts" => [part], "role" => "model"}}]})
  end

  describe "a signature sent in a chunk of its own" do
    before do
      parse!({"functionCall" => {"name" => "system", "args" => {"command" => "date"}}})
      parse!({"thoughtSignature" => "abc123"})
    end

    it "is folded into the part it belongs to" do
      expect(parts.size).to eq(1)
    end

    it "is carried on that part" do
      expect(parts.first["thoughtSignature"]).to eq("abc123")
    end

    it "leaves the function call intact" do
      expect(parts.first["functionCall"]["name"]).to eq("system")
    end
  end

  describe "a signature sent beside other content" do
    let(:inline) { {"mimeType" => "image/png", "data" => "AAAA"} }

    before { parse!({"inlineData" => inline, "thoughtSignature" => "abc123"}) }

    it "is appended as one part" do
      expect(parts.size).to eq(1)
    end

    it "keeps the content it was sent with" do
      expect(parts.first["inlineData"]).to eq(inline)
    end

    it "keeps the signature" do
      expect(parts.first["thoughtSignature"]).to eq("abc123")
    end
  end
end
