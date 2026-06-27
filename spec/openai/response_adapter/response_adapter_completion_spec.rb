# frozen_string_literal: true

require "setup"

RSpec.describe "LLM::OpenAI::ResponseAdapter::Completion" do
  let!(:provider) { LLM.openai(key: "test") }
  let(:body) { LLM::Object.from(choices: [], usage:, model: "test-model") }
  let(:http_response) { Struct.new(:body).new(body) }
  let(:response) { LLM::Response.new(http_response) }
  let(:completion) { LLM::OpenAI::ResponseAdapter.adapt(response, type: :completion) }

  context "when usage is nil" do
    let(:usage) { nil }

    it "returns 0 for input tokens" do
      expect(completion.input_tokens).to eq(0)
    end

    it "returns 0 for output tokens" do
      expect(completion.output_tokens).to eq(0)
    end

    it "returns 0 for total tokens" do
      expect(completion.total_tokens).to eq(0)
    end
  end

  context "when choices are missing" do
    let(:usage) { nil }
    let(:body) { LLM::Object.from(usage:, model: "test-model") }

    it "returns no messages" do
      expect(completion.messages).to eq([])
    end
  end

  context "when usage is provided" do
    let(:usage) do
      LLM::Object.from(
        prompt_tokens: 10,
        completion_tokens: 20,
        total_tokens: 30,
        prompt_tokens_details: {audio_tokens: 2, image_tokens: 4},
        completion_tokens_details: {audio_tokens: 3}
      )
    end

    it "returns correct input tokens" do
      expect(completion.input_tokens).to eq(10)
    end

    it "returns correct output tokens" do
      expect(completion.output_tokens).to eq(20)
    end

    it "returns correct input audio tokens" do
      expect(completion.input_audio_tokens).to eq(2)
    end

    it "returns correct output audio tokens" do
      expect(completion.output_audio_tokens).to eq(3)
    end

    it "returns correct input image tokens" do
      expect(completion.input_image_tokens).to eq(4)
    end

    it "returns correct total tokens" do
      expect(completion.total_tokens).to eq(30)
    end
  end

  context "when a tool call has malformed json arguments" do
    let(:usage) { nil }
    let(:body) do
      LLM::Object.from(
        choices: [
          {
            message: {
              role: "assistant",
              content: "",
              tool_calls: [
                {
                  id: "call_1",
                  function: {
                    name: "system",
                    arguments: "{\"command\":\"date"
                  }
                }
              ]
            }
          }
        ],
        usage:,
        model: "test-model"
      )
    end

    it "tolerates malformed tool arguments" do
      expect { completion.choices }.not_to raise_error
      tool = completion.choices[0].extra[:tool_calls][0]
      expect(tool.id).to eq("call_1")
      expect(tool.name).to eq("system")
    end
  end

  context "when the assistant message has reasoning content" do
    let(:usage) { nil }
    let(:body) do
      LLM::Object.from(
        choices: [
          {
            message: {
              role: "assistant",
              content: "323",
              reasoning_content: "17 times 19 is 17 times 20 minus 17."
            }
          }
        ],
        usage:,
        model: "test-model"
      )
    end

    it "returns reasoning content from the assistant message" do
      expect(completion.reasoning_content).to eq("17 times 19 is 17 times 20 minus 17.")
    end
  end
end
