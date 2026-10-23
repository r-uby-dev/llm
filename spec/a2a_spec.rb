# frozen_string_literal: true

require "setup"

RSpec.describe LLM::A2A do
  let(:transport_class) do
    Class.new do
      attr_reader :gets, :posts, :deletes, :streams

      def initialize(responses)
        @responses = responses
        @gets = []
        @posts = []
        @deletes = []
        @streams = []
      end

      def get(path)
        @gets << path
        @responses.fetch([:get, path])
      end

      def post(path, body)
        @posts << [path, body]
        @responses.fetch([:post, path])
      end

      def delete(path)
        @deletes << path
        @responses.fetch([:delete, path])
      end

      def get_stream(path)
        @streams << [:get, path]
        @responses.fetch([:get_stream, path], []).each { yield it }
      end

      def post_stream(path, body)
        @streams << [:post, path, body]
        @responses.fetch([:post_stream, path], []).each { yield it }
      end
    end
  end

  let(:responses) { {} }
  let(:transport) { transport_class.new(responses) }
  let(:a2a) { described_class.new(transport:, binding: :rest) }

  describe "#send_message" do
    let(:responses) do
      {
        [:post, "/message:send"] => {
          "task" => {"id" => "task_1"}
        }
      }
    end

    it "includes metadata when given" do
      a2a.send_message("hello", {}, metadata: {"tenant" => "acme"})
      expect(transport.posts[0][-1][:metadata]).to eq("tenant" => "acme")
    end
  end

  describe "#card" do
    subject(:card) { a2a.card }

    let(:responses) do
      {
        [:get, "/.well-known/agent-card.json"] => {
          "name" => "Data Analyzer",
          "skills" => [
            {"id" => "analyze", "name" => "analyze", "description" => "Analyze data"}
          ],
          "signatures" => [
            {"protected" => "eyJhbGciOiJFZERTQSJ9", "signature" => "abc123"}
          ],
          "capabilities" => {
            "streaming" => true,
            "extensions" => [
              {"uri" => "https://example.com/extensions/history"}
            ]
          }
        }
      }
    end

    it "wraps signatures" do
      expect(card.signatures[0].signature).to eq("abc123")
    end

    it "wraps capability extensions" do
      expect(card.capabilities.extensions[0].uri).to eq("https://example.com/extensions/history")
    end
  end

  describe "#tasks" do
    subject(:tasks) { a2a.tasks }

    context "when getting a task" do
      let(:responses) do
        {
          [:get, "/tasks/task_1"] => {
            "id" => "task_1",
            "status" => {"state" => "TASK_STATE_COMPLETED"}
          }
        }
      end

      it "returns the task" do
        expect(tasks.get("task_1").id).to eq("task_1")
      end
    end

    context "when subscribing to a task" do
      let(:responses) do
        {
          [:get_stream, "/tasks/task_1:subscribe"] => [
            {"event" => "task", "taskId" => "task_1"}
          ]
        }
      end

      it "uses the task subscribe endpoint" do
        tasks.subscribe("task_1") { nil }
        expect(transport.streams).to eq([[:get, "/tasks/task_1:subscribe"]])
      end
    end

    context "when listing tasks" do
      let(:path) do
        "/tasks?contextId=ctx_1&status=completed" \
        "&historyLength=10" \
        "&statusTimestampAfter=2026-05-20T00%3A00%3A00Z" \
        "&includeArtifacts=true" \
        "&pageSize=5" \
        "&pageToken=next"
      end

      let(:responses) do
        {
          [:get, path] => {"tasks" => []}
        }
      end

      it "includes the optional query params" do
        tasks.list(context_id: "ctx_1", status: "completed", history_length: 10,
                   status_timestamp_after: "2026-05-20T00:00:00Z",
                   include_artifacts: true, page_size: 5, page_token: "next")
        expect(transport.gets[0]).to eq(path)
      end
    end

    context "when cancelling a task" do
      let(:responses) do
        {
          [:post, "/tasks/task_1:cancel"] => {
            "id" => "task_1"
          }
        }
      end

      it "includes metadata when given" do
        tasks.cancel("task_1", metadata: {"reason" => "user_request"})
        expect(transport.posts[0][-1][:metadata]).to eq("reason" => "user_request")
      end
    end
  end

  describe "#notifications" do
    subject(:notifications) { a2a.notifications }

    let(:responses) do
      {
        [:get, "/tasks/task_1/pushNotificationConfigs"] => {
          "configs" => [
            {"id" => "cfg_1", "url" => "https://client.example.com/webhook"}
          ]
        }
      }
    end

    it "lists push notification configs" do
      expect(notifications.list("task_1").configs[0].id).to eq("cfg_1")
    end
  end

  describe "when given the hello-world example from a2a-samples" do
    let(:transport) do
      Class.new do
        attr_reader :gets, :posts, :streams

        def initialize
          @gets = []
          @posts = []
          @streams = []
        end

        def get(path)
          @gets << path
          case path
          when "/.well-known/agent-card.json" then public_card
          else raise KeyError, path
          end
        end

        def post(path, body)
          @posts << [path, body]
          case body[:method]
          when "SendMessage" then task_response
          when "GetExtendedAgentCard" then extended_card
          else raise KeyError, body[:method]
          end
        end

        def post_stream(path, body)
          @streams << [path, body]
          case body[:method]
          when "SendStreamingMessage" then stream_events.each { yield(it) }
          else raise KeyError, body[:method]
          end
        end

        private

        def public_card
          {
            "name" => "Hello World Agent",
            "description" => "Just a hello world agent",
            "version" => "0.0.1",
            "capabilities" => {"streaming" => true, "extendedAgentCard" => true},
            "supportedInterfaces" => [
              {"protocolBinding" => "JSONRPC", "protocolVersion" => "1.0", "url" => "http://127.0.0.1:9999"}
            ],
            "defaultInputModes" => ["text/plain"],
            "defaultOutputModes" => ["text/plain"],
            "skills" => [
              {
                "id" => "hello_world",
                "name" => "Returns hello world",
                "description" => "just returns hello world",
                "tags" => ["hello world"],
                "examples" => ["hi", "hello world"]
              }
            ]
          }
        end

        def extended_card
          public_card.merge(
            "name" => "Hello World Agent - Extended Edition",
            "version" => "0.0.2",
            "skills" => public_card["skills"] + [
              {
                "id" => "super_hello_world",
                "name" => "Returns a SUPER Hello World",
                "description" => "A more enthusiastic greeting, only for authenticated users.",
                "tags" => ["hello world", "super", "extended"],
                "examples" => ["super hi", "give me a super hello"]
              }
            ]
          )
        end

        def task_response
          {
            "task" => {
              "id" => "task_1",
              "status" => {"state" => "TASK_STATE_COMPLETED"},
              "artifacts" => [
                {"parts" => [{"text" => "Hello, World!"}]}
              ]
            }
          }
        end

        def stream_events
          [
            {"task" => {"id" => "task_1"}},
            {"status" => {"state" => "TASK_STATE_WORKING"}},
            {"artifact" => {"parts" => [{"text" => "Hello, World!"}]}},
            {"status" => {"state" => "TASK_STATE_COMPLETED"}}
          ]
        end
      end.new
    end
    let(:a2a) { described_class.new(transport:, binding: :jsonrpc) }

    describe "#card" do
      let(:card) { a2a.card }

      it "loads the public hello world card" do
        expect(card.name).to eq("Hello World Agent")
      end
    end

    describe "#extended_card" do
      let(:card) { a2a.extended_card }
      let(:skills) { card.skills }

      it "loads the extended hello world card" do
        expect(skills[-1].name).to eq("Returns a SUPER Hello World")
      end
    end

    describe "#send_message" do
      let(:message) { a2a.send_message("hi") }
      let(:artifacts) { message.task.artifacts }

      it "returns the hello world task artifact" do
        expect(artifacts[0].parts[0].text).to eq("Hello, World!")
      end
    end

    describe "#send_streaming_message" do
      let(:events) { [] }

      before do
        a2a.send_streaming_message("hi") { events << it }
      end

      it "yields the hello world stream events" do
        expect(events[-1].status.state).to eq("TASK_STATE_COMPLETED")
      end
    end

    describe "#skills" do
      let(:tool) { a2a.skills[0] }
      let(:result) { tool.new.call(input: "hi") }
      let(:artifacts) { result[:task].task.artifacts }

      it "adapts the hello world skill as a tool" do
        expect(artifacts[0].parts[0].text).to eq("Hello, World!")
      end
    end
  end

  describe "with a base path" do
    let(:responses) do
      {
        [:get, "/tenant-1/tasks/task_1"] => {
          "id" => "task_1"
        }
      }
    end

    let(:a2a) { described_class.new(transport:, binding: :rest, base_path: "/tenant-1") }

    it "prefixes REST task paths" do
      expect(a2a.tasks.get("task_1").id).to eq("task_1")
      expect(transport.gets[0]).to eq("/tenant-1/tasks/task_1")
    end
  end

  describe ".rest" do
    let(:client) do
      described_class.rest(url: "https://agent.example.com", transport: :net_http_persistent)
    end

    it "builds an A2A client over an HTTP transport" do
      expect(client).to be_a(LLM::A2A)
    end
  end

  describe ".jsonrpc" do
    let(:client) do
      described_class.jsonrpc(url: "https://agent.example.com", transport: :net_http_persistent)
    end

    it "builds an A2A client over an HTTP transport" do
      expect(client).to be_a(LLM::A2A)
    end
  end
end
