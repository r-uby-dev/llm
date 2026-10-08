# frozen_string_literal: true

require "setup"
require "tempfile"
require "llm/providers/deepseek"

RSpec.describe "LLM::DeepSeek::RequestAdapter::Completion" do
  describe "#adapt" do
    subject(:payload) { LLM::DeepSeek::RequestAdapter::Completion.new(message).adapt }

    let(:provider) { LLM.deepseek(key: "test") }

    context "with assistant content" do
      let(:message) do
        LLM::Message.new("assistant", "answer", reasoning_content: "thought")
      end

      it "preserves reasoning content" do
        expect(payload).to eq(
          role: "assistant",
          content: [{type: :text, text: "answer"}],
          reasoning_content: "thought"
        )
      end
    end

    context "with image content" do
      let(:message) do
        LLM::Message.new("user", [ctx.image_url("https://example.com/cat.png")])
      end

      let(:ctx) { LLM::Context.new(provider) }

      it "adapts the image url" do
        expect(payload).to eq(
          role: "user",
          content: [{type: :image_url, image_url: {url: "https://example.com/cat.png"}}]
        )
      end
    end

    context "with a local image" do
      let(:message) do
        LLM::Message.new("user", [ctx.local_file(image)])
      end

      let(:ctx) { LLM::Context.new(provider) }
      let(:image) { File.join(Dir.getwd, "spec", "fixtures", "images", "bluebook.png") }

      it "adapts the image as a base64 encoded data uri" do
        expect(payload).to eq(
          role: "user",
          content: [{
            type: :image_url,
            image_url: {url: "data:image/png;base64,#{LLM.File(image).to_b64}"}
          }]
        )
      end
    end

    context "with local file content" do
      let(:tempfile) do
        Tempfile.create(["example", ".pdf"]).tap {
          _1.write("%PDF-1.4\n")
          _1.rewind
        }
      end

      let(:message) do
        LLM::Message.new("user", [ctx.local_file(tempfile.path)])
      end

      after do
        tempfile.close
        File.delete(tempfile.path)
      end

      let(:ctx) { LLM::Context.new(provider) }

      it "raises a prompt error that says it is not an image" do
        expect { payload }.to raise_error(LLM::PromptError, /is not an image/)
      end
    end

    context "with remote file content" do
      let(:message) do
        LLM::Message.new("user", [ctx.remote_file(remote_file)])
      end

      let(:ctx) { LLM::Context.new(provider) }
      let(:remote_file) do
        LLM::Object.from("file?" => true, "id" => "file_123", "mime_type" => "image/png")
      end

      it "adapts the remote file as a file content block" do
        expect(payload).to eq(
          role: "user",
          content: [{type: :file, file_id: "file_123"}]
        )
      end
    end

    context "with response content" do
      let(:message) do
        LLM::Message.new("user", [response])
      end

      let(:response) do
        response!(choices: [LLM::Message.new("assistant", "hello")])
      end

      it "raises a prompt error that says the response is not a file" do
        expect { payload }.to raise_error(LLM::PromptError, /not supported by the DeepSeek API/)
      end
    end

    context "with assistant tool calls" do
      let(:message) do
        LLM::Message.new("assistant", nil, {
          reasoning_content: "thought",
          original_tool_calls: [{"id" => "call_1"}],
          tool_calls: [{id: "call_1", name: "system", arguments: {command: "date"}}]
        })
      end

      it "preserves nil content" do
        expect(payload[:content]).to be_nil
      end

      it "normalizes tool calls" do
        expect(payload[:tool_calls]).to eq([{"id" => "call_1"}])
      end

      it "preserves reasoning content" do
        expect(payload[:reasoning_content]).to eq("thought")
      end
    end
  end
end

RSpec.describe "LLM::DeepSeek::RequestAdapter schema adaptation" do
  let(:provider) { LLM.deepseek(key: "test") }

  let(:schema) do
    Class.new(LLM::Schema) do
      property :name, String, "name", required: true
      property :age, Integer, "age"
    end
  end

  describe "#normalize_complete_params" do
    subject(:normalized) { provider.send(:normalize_complete_params, schema:) }

    it "sets json_object response format" do
      params, = normalized
      expect(params[:response_format]).to eq(type: "json_object")
    end

    it "injects a system message describing the schema" do
      params, = normalized
      expect(params[:messages].size).to eq(1)
      expect(params[:messages].first.role).to eq("system")
      expect(params[:messages].first.content).to include("Respond with a single valid JSON object.")
      expect(params[:messages].first.content).to include("name: string (required) - name")
      expect(params[:messages].first.content).to include("age?: integer - age")
    end
  end
end
