# frozen_string_literal: true

require "setup"
require "llm/tools/rg"

RSpec.describe LLM::Tool::Rg do
  let(:tool) { described_class.new }
  let(:result) { {ok: true, stdout: "match\n", stderr: ""} }

  before do
    allow(tool).to receive(:execute).and_return(result)
  end

  describe ".function" do
    let(:params) { described_class.function.params }

    it "defines the patterns param" do
      expect(params.properties[:patterns]).to be_a(LLM::Schema::Array)
    end

    it "marks the patterns param as required" do
      expect(params.properties[:patterns]).to be_required
    end

    it "does not default the path to the cwd of this process" do
      expect(params.properties[:path].default).to be_nil
    end
  end

  describe "#call" do
    it "runs rg through #execute" do
      tool.call(patterns: %w[foo bar])
      expect(tool).to have_received(:execute).with(
        command: "rg",
        arguments: ["-m", 10, "-e", "foo", "-e", "bar"],
        timeout: 5,
        max_bytes: described_class.max_bytes
      )
    end

    it "returns the result" do
      expect(tool.call(patterns: %w[foo])).to eq(result)
    end

    it "forwards the timeout" do
      tool.call(patterns: %w[foo], timeout: 9)
      expect(tool).to have_received(:execute)
        .with(hash_including(timeout: 9))
    end

    it "forwards the path" do
      tool.call(patterns: %w[foo], path: "/tmp")
      expect(tool).to have_received(:execute)
        .with(hash_including(command: "rg", arguments: ["-m", 10, "-e", "foo", "/tmp"]))
    end

    it "passes a custom max count" do
      tool.call(patterns: %w[foo], max_count: 5)
      expect(tool).to have_received(:execute)
        .with(hash_including(command: "rg", arguments: ["-m", 5, "-e", "foo"]))
    end

    it "passes the max chars" do
      tool.call(patterns: %w[foo], max_bytes: 100)
      expect(tool).to have_received(:execute)
        .with(hash_including(max_bytes: 100))
    end
  end

  describe "validation" do
    it "raises when max_count is not a positive integer" do
      expect { tool.call(patterns: %w[foo], max_count: "x") }
        .to raise_error("max_count must be a positive integer")
    end

    it "raises when max_count is zero" do
      expect { tool.call(patterns: %w[foo], max_count: 0) }
        .to raise_error("max_count must be a positive integer")
    end

    it "raises when the path is the root" do
      expect { tool.call(patterns: %w[foo], path: "/") }
        .to raise_error("you can't search from the root of the filesystem")
    end

    it "raises when patterns is [\".\"]" do
      expect { tool.call(patterns: ["."]) }.to raise_error("narrow your search")
    end
  end
end
