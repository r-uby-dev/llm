# frozen_string_literal: true

require "setup"

RSpec.describe "Google parallel tool stream" do
  let(:provider) { LLM.google(key: "fixture") }
  let(:weather) do
    LLM.function(:weather) do |fn|
      fn.params { it.object(city: it.string.required) }
      fn.define { |city:| {city:} }
    end
  end
  let(:parts) do
    [
      {"functionCall" => {"id" => "paris", "name" => "weather", "args" => {"city" => "Paris"}}},
      {"functionCall" => {"id" => "berlin", "name" => "weather", "args" => {"city" => "Berlin"}}}
    ]
  end
  let(:stream) do
    Class.new(LLM::Stream) do
      attr_reader :calls
      def initialize = @calls = []
      def on_tool_call(function) = @calls << function
    end.new.tap { it.extra[:tools] = [weather] }
  end

  [true, false].product([true, false]).each do |one_frame, ids|
    it "matches non-streaming calls with one_frame=#{one_frame}, ids=#{ids}" do
      calls = ids ? parts : parts.map { it.merge("functionCall" => it["functionCall"].except("id")) }
      body = {"candidates" => [{"index" => 0, "content" => {"role" => "model", "parts" => calls}}]}
      stub_request(:post, %r{generativelanguage.googleapis.com/.+:generateContent})
        .to_return(status: 200, headers: {"Content-Type" => "application/json"}, body: JSON.generate(body))
      expected = provider.complete("weather", tools: [weather]).messages.flat_map(&:functions)
      frames = one_frame ? [body] : calls.map do |part|
        {"candidates" => [{"index" => 0, "content" => {"role" => "model", "parts" => [part]}}]}
      end
      stub_request(:post, %r{generativelanguage.googleapis.com/.+:streamGenerateContent})
        .to_return(status: 200, headers: {"Content-Type" => "text/event-stream"}, body: frames.map { "data: #{JSON.generate(it)}\n\n" }.join)
      response = provider.complete("weather", tools: [weather], stream:)
      actual = response.messages.flat_map(&:functions)
      expect(actual.map(&:arguments)).to eq(expected.map(&:arguments))
      expect(actual.map(&:id)).to eq(expected.map(&:id))
      expect(stream.calls.map(&:arguments)).to eq(expected.map(&:arguments))
      expect(stream.calls.map(&:id)).to eq(expected.map(&:id))
    end
  end
end
