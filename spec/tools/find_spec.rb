# frozen_string_literal: true

require "setup"
require "llm/tools/unix"

RSpec.describe LLM::Tool::Unix::Find do
  let(:tool) { described_class.new }
  let(:result) { {ok: true, stdout: "lib/llm.rb\nlib/llm/tool.rb\n", stderr: ""} }

  before do
    allow(tool).to receive(:execute).and_return(result)
  end

  describe ".function" do
    let(:params) { described_class.function.params }

    it "defines the kind of a path as an enum" do
      expect(params.properties[:type].enum).to eq(%w[f d l])
    end

    it "defines the path, name, type, max_depth, newer_than, limit, timeout and max_bytes params" do
      expect(params.properties.keys).to contain_exactly(
        "path", "name", "type", "max_depth", "newer_than", "limit",
        "timeout", "max_bytes"
      )
    end

    it "does not default the path to the cwd of this process" do
      expect(params.properties[:path].default).to be_nil
    end
  end

  describe "#call" do
    it "walks the path with no primaries" do
      tool.call(path: Dir.getwd)
      expect(tool).to have_received(:execute).with(
        command: "find",
        arguments: [Dir.getwd, "-print"],
        timeout: 5,
        max_bytes: described_class.max_bytes
      )
    end

    it "leaves the path out so find walks the cwd of the command" do
      tool.call
      expect(tool).to have_received(:execute)
        .with(hash_including(arguments: ["-print"]))
    end

    it "passes the name as a glob" do
      tool.call(path: Dir.getwd, name: "*.rb")
      expect(tool).to have_received(:execute)
        .with(hash_including(arguments: [Dir.getwd, "-name", "*.rb", "-print"]))
    end

    it "passes the type" do
      tool.call(path: Dir.getwd, type: "d")
      expect(tool).to have_received(:execute)
        .with(hash_including(arguments: [Dir.getwd, "-type", "d", "-print"]))
    end

    it "passes the max depth" do
      tool.call(path: Dir.getwd, max_depth: 2)
      expect(tool).to have_received(:execute)
        .with(hash_including(arguments: [Dir.getwd, "-maxdepth", "2", "-print"]))
    end

    it "passes the age as an mmin primary" do
      tool.call(path: Dir.getwd, newer_than: 60)
      expect(tool).to have_received(:execute)
        .with(hash_including(arguments: [Dir.getwd, "-mmin", "-60", "-print"]))
    end

    it "passes every primary in a fixed order" do
      arguments = [Dir.getwd, "-maxdepth", "3", "-type", "f", "-name", "*.rb", "-mmin", "-5", "-print"]
      tool.call(path: Dir.getwd, name: "*.rb", type: "f", max_depth: 3, newer_than: 5)
      expect(tool).to have_received(:execute).with(hash_including(arguments:))
    end

    it "forwards the timeout" do
      tool.call(path: Dir.getwd, timeout: 9)
      expect(tool).to have_received(:execute).with(hash_including(timeout: 9))
    end

    it "passes the max bytes" do
      tool.call(path: Dir.getwd, max_bytes: 100)
      expect(tool).to have_received(:execute).with(hash_including(max_bytes: 100))
    end

    it "returns the paths" do
      expect(tool.call(path: Dir.getwd)).to eq(
        {ok: true, paths: ["lib/llm.rb", "lib/llm/tool.rb"], count: 2, truncated: false}
      )
    end

    it "caps the paths at the limit and says it did" do
      expect(tool.call(path: Dir.getwd, limit: 1)).to eq(
        {ok: true, paths: ["lib/llm.rb"], count: 1, truncated: true}
      )
    end

    it "returns the result as it is when find failed" do
      allow(tool).to receive(:execute)
        .and_return({ok: false, stdout: "", stderr: "find: nope: No such file\n"})
      expect(tool.call(path: Dir.getwd)).to eq(
        {ok: false, stdout: "", stderr: "find: nope: No such file\n"}
      )
    end
  end

  describe "validation" do
    it "raises when the path is the root of the filesystem" do
      expect { tool.call(path: "/") }
        .to raise_error("you can't search from the root of the filesystem")
    end

    it "raises when the path does not exist" do
      expect { tool.call(path: "/nope/nope") }
        .to raise_error("path does not exist: /nope/nope")
    end

    it "raises when the max depth is negative" do
      expect { tool.call(path: Dir.getwd, max_depth: -1) }
        .to raise_error("max_depth must be a non-negative integer")
    end

    it "raises when the age is not a positive integer" do
      expect { tool.call(path: Dir.getwd, newer_than: 0) }
        .to raise_error("newer_than must be a positive integer")
    end

    it "raises when the limit is not a positive integer" do
      expect { tool.call(path: Dir.getwd, limit: 0) }
        .to raise_error("limit must be a positive integer")
    end
  end
end
