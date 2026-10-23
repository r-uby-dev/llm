# frozen_string_literal: true

require "setup"

RSpec.describe "LLM::Bedrock" do
  class ReportSchema < LLM::Schema
    property :name, String, "Report name", required: true
  end

  let(:provider) do
    LLM.bedrock(
      access_key_id: "AKIA_TEST",
      secret_access_key: "SECRET",
      region: "us-east-1"
    )
  end
  let(:url) { "https://bedrock-runtime.us-east-1.amazonaws.com/model/test-model/converse" }
  let(:response_body) do
    {
      output: {message: {role: "assistant", content: [{text: "pong"}]}},
      usage: {inputTokens: 1, outputTokens: 1},
      modelId: "test-model"
    }
  end
  let(:schema_builder) { provider.schema }
  let(:schema) do
    schema_builder.object(
      name: schema_builder.string.required,
      strict: schema_builder.boolean,
      "$schema": schema_builder.string
    )
  end

  context "when replaying assistant tool calls" do
    let(:message) do
      LLM::Message.new(:assistant, "", tool_calls: [{id: "call_1", name: "system", arguments: {command: "date"}}])
    end

    it "omits blank text content blocks" do
      expect(LLM::Bedrock::RequestAdapter::Completion.new(provider, message).adapt).to eq(
        role: "assistant",
        content: [
          {
            toolUse: {
              toolUseId: "call_1",
              name: "system",
              input: {command: "date"}
            }
          }
        ]
      )
    end
  end

  context "when given system messages" do
    let(:prompt) do
      LLM::Prompt.new(provider) do
        system "Be terse."
        user "ping"
      end
    end

    before do
      stub_request(:post, url)
        .to_return(
          status: 200,
          body: LLM.json.dump(response_body),
          headers: {"Content-Type" => "application/json"}
        )
      provider.complete(prompt, model: "test-model")
    end

    it "sends them in the top-level system field" do
      expect(WebMock).to have_requested(:post, url).with { |request|
        body = LLM.json.load(request.body)
        expect(body["system"]).to eq([{"text" => "Be terse."}])
        expect(body["messages"]).to eq([{"role" => "user", "content" => [{"text" => "ping"}]}])
      }
    end
  end

  context "when given a schema" do
    let(:prompt) do
      LLM::Prompt.new(provider) do
        system "Be terse."
        user "Return JSON."
      end
    end

    before do
      stub_request(:post, url)
        .to_return(
          status: 200,
          body: LLM.json.dump(response_body),
          headers: {"Content-Type" => "application/json"}
        )
    end

    it "sends system and outputConfig in the request body" do
      provider.complete(prompt, model: "test-model", schema:)
      expect(WebMock).to have_requested(:post, url).with { |request|
        body = LLM.json.load(request.body)
        expect(body["system"]).to eq([{"text" => "Be terse."}])
        expect(body["outputConfig"]).to include("textFormat" => include(
          "type" => "json_schema",
          "structure" => include("jsonSchema" => include("name" => "response"))
        ))
      }
    end

    it "stringifies the schema" do
      provider.complete(prompt, model: "test-model", schema:)
      expect(WebMock).to have_requested(:post, url).with { |request|
        body = LLM.json.load(request.body)
        value = body.dig("outputConfig", "textFormat", "structure", "jsonSchema", "schema")
        expect(value).to be_a(String)
        expect(LLM.json.load(value)).to include("type" => "object", "properties" => include("name" => anything))
      }
    end

    it "accepts class-based schemas" do
      provider.complete(prompt, model: "test-model", schema: ReportSchema)
      expect(WebMock).to have_requested(:post, url).with { |request|
        body = LLM.json.load(request.body)
        value = body.dig("outputConfig", "textFormat", "structure", "jsonSchema", "schema")
        expect(LLM.json.load(value)).to include("type" => "object", "properties" => include("name" => anything))
      }
    end

    it "removes Bedrock-incompatible keys" do
      provider.complete(prompt, model: "test-model", schema:)
      expect(WebMock).to have_requested(:post, url).with { |request|
        body = LLM.json.load(request.body)
        value = LLM.json.load(body.dig("outputConfig", "textFormat", "structure", "jsonSchema", "schema"))
        expect(value).not_to have_key("strict")
        expect(value).not_to have_key("$schema")
      }
    end
  end

  context "when not given a schema" do
    before do
      stub_request(:post, url)
        .to_return(
          status: 200,
          body: LLM.json.dump(response_body),
          headers: {"Content-Type" => "application/json"}
        )
      provider.complete("ping", model: "test-model")
    end

    it "does not send outputConfig" do
      expect(WebMock).to have_requested(:post, url).with { |request|
        body = LLM.json.load(request.body)
        expect(body).not_to have_key("outputConfig")
      }
    end
  end
end
