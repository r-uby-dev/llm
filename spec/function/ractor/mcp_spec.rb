# frozen_string_literal: true

require "setup"

RSpec.describe "ractor: mcp tools" do
  let(:server) { File.expand_path("../../support/mcp/server.rb", __dir__) }
  let(:definition) do
    {
      "name" => "echo",
      "description" => "Echoes text",
      "inputSchema" => {
        "type" => "object",
        "properties" => {"text" => {"type" => "string"}},
        "required" => ["text"]
      }
    }
  end
  let(:function) do
    LLM::Tool.mcp(mcp, definition).function.dup.tap do |fn|
      fn.id = "call_1"
      fn.arguments = {"text" => "hello"}
    end
  end
  let(:result) { function.task(:ractor).wait.to_h }

  shared_examples "an MCP tool in a ractor" do
    it "returns the tool's result" do
      expect(result).to eq(id: "call_1", name: "echo", value: {"message" => "echo: hello"})
    end
  end

  context "with the stdio transport" do
    let(:mcp) { LLM::MCP.stdio(argv: [RbConfig.ruby, server]) }

    it_behaves_like "an MCP tool in a ractor"
  end

  context "with the http transport" do
    before { WebMock.disable! }
    after { WebMock.enable! }

    let(:port) { 20_000 + rand(20_000) }
    let(:mcp) { LLM::MCP.http(url: "http://127.0.0.1:#{port}/") }
    let!(:pid) do
      pid = Process.spawn(RbConfig.ruby, server, "--http", port.to_s, out: File::NULL, err: File::NULL)
      sleep 0.5
      pid
    end

    after do
      Process.kill("TERM", pid)
      Process.wait(pid)
    end

    it_behaves_like "an MCP tool in a ractor"
  end
end
