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

  describe "parallel and partial function calls" do
    let(:weather) do
      LLM.function(:weather) do |fn|
        fn.params { it.object(city: it.string.required) }
        fn.define { |city:| {city:} }
      end
    end

    before { stream.extra[:tools] = [weather] }

    [true, false].each do |ids|
      it "keeps two complete same-name calls separate with ids=#{ids}" do
        first = {"name" => "weather", "args" => {"city" => "Paris"}}
        second = {"name" => "weather", "args" => {"city" => "Berlin"}}
        first["id"], second["id"] = "paris", "berlin" if ids
        parse!({"functionCall" => first, "thoughtSignature" => "signature-a"})
        parse!({"functionCall" => second, "thoughtSignature" => "signature-b"})
        expect(parts.size).to eq(2)
        expect(parts.map { it["functionCall"]["args"] }).to eq([{"city" => "Paris"}, {"city" => "Berlin"}])
        expect(parts.map { it["thoughtSignature"] }).to eq(%w[signature-a signature-b])
        expect(stream.calls.map(&:arguments)).to eq([{"city" => "Paris"}, {"city" => "Berlin"}])
        expect(stream.calls.map(&:id).uniq.size).to eq(2)
      end
    end

    it "merges an incomplete call before emitting it" do
      parse!({"functionCall" => {"name" => "weather"}})
      expect(stream.calls).to be_empty
      parse!({"functionCall" => {"args" => {"city" => "Paris"}}})
      expect(parts.size).to eq(1)
      expect(stream.calls.map(&:arguments)).to eq([{"city" => "Paris"}])
      parse!({"thoughtSignature" => "signature"})
      expect(parts.first["thoughtSignature"]).to eq("signature")
    end

    it "keeps preceding text separate from a partial call" do
      parse!({"text" => "Checking the weather."})
      parse!({"functionCall" => {"name" => "weather"}})
      expect(stream.calls).to be_empty
      parse!({"functionCall" => {"args" => {"city" => "Paris"}}})
      expect(parts.size).to eq(2)
      expect(parts.first).to eq({"text" => "Checking the weather."})
      expect(stream.calls.map(&:arguments)).to eq([{"city" => "Paris"}])
    end

    it "starts a partial second call when its id changes" do
      parse!({"functionCall" => {"id" => "paris", "name" => "weather", "args" => {"city" => "Paris"}}})
      parse!({"functionCall" => {"id" => "berlin", "name" => "weather"}})
      parse!({"functionCall" => {"id" => "berlin", "args" => {"city" => "Berlin"}}})
      expect(parts.size).to eq(2)
      expect(stream.calls.map(&:arguments)).to eq([{"city" => "Paris"}, {"city" => "Berlin"}])
    end

    it "keeps different function names as different calls" do
      other = LLM.function(:forecast) do |fn|
        fn.params { it.object(city: it.string.required) }
        fn.define { |city:| {city:} }
      end
      stream.extra[:tools] << other
      parse!({"functionCall" => {"name" => "weather", "args" => {"city" => "Paris"}}})
      parse!({"functionCall" => {"name" => "forecast", "args" => {"city" => "Berlin"}}})
      expect(parts.size).to eq(2)
      expect(stream.calls.map(&:name)).to eq(%i[weather forecast])
    end

    it "keeps same-id metadata updates on the existing call" do
      call = {"id" => "paris", "name" => "weather", "args" => {"city" => "Paris"}}
      parse!({"functionCall" => call})
      parse!({"functionCall" => call.dup, "thoughtSignature" => "signature"})
      expect(parts.size).to eq(1)
      expect(stream.calls.size).to eq(1)
      expect(parts.first["thoughtSignature"]).to eq("signature")
    end
  end

end
