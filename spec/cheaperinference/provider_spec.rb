# frozen_string_literal: true

require "setup"

RSpec.describe "LLM::CheaperInference" do
  subject(:provider) { LLM.cheaperinference(key: "TOKEN") }

  let(:response_body) do
    JSON.dump(
      id: "chatcmpl-test",
      object: "chat.completion",
      created: 0,
      model: "gpt-5.4-mini",
      choices: [{index: 0, message: {role: "assistant", content: "pong"}, finish_reason: "stop"}],
      usage: {prompt_tokens: 1, completion_tokens: 1, total_tokens: 2}
    )
  end

  it "builds the Cheaper Inference provider with its API defaults" do
    expect(provider).to be_a(LLM::OpenAI)
    expect(provider.name).to eq(:cheaperinference)
    expect(provider.default_model).to eq("gpt-5.4-mini")
    expect(provider.instance_variable_get(:@host)).to eq("api.cheaperinference.com")
    expect(provider.instance_variable_get(:@base_path)).to eq("/v1")
  end

  it "sends chat completions" do
    request = stub_request(:post, "https://api.cheaperinference.com/v1/chat/completions")
      .with(
        headers: {"Authorization" => "Bearer TOKEN"},
        body: hash_including("model" => "gpt-5.4-mini")
      )
      .to_return(status: 200, headers: {"Content-Type" => "application/json"}, body: response_body)

    response = provider.complete("ping")

    expect(request).to have_been_requested.once
    expect(response.content).to eq("pong")
  end

  it "uses text-embedding-3-small for embeddings" do
    request = stub_request(:post, "https://api.cheaperinference.com/v1/embeddings")
      .with(body: hash_including("model" => "text-embedding-3-small"))
      .to_return(
        status: 200,
        headers: {"Content-Type" => "application/json"},
        body: JSON.dump(
          object: "list",
          model: "text-embedding-3-small",
          data: [{object: "embedding", index: 0, embedding: [0.1, 0.2]}],
          usage: {prompt_tokens: 1, total_tokens: 1}
        )
      )

    response = provider.embed("ping")

    expect(request).to have_been_requested.once
    expect(response.embeddings).to eq([[0.1, 0.2]])
  end

  it "does not expose unsupported OpenAI APIs" do
    %i[files images audio moderations vector_stores].each do |api|
      expect { provider.public_send(api) }.to raise_error(NotImplementedError)
    end
  end
end
