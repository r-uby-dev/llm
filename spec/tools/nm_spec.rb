# frozen_string_literal: true

require "setup"
require "llm/tools/unix"

RSpec.describe LLM::Tool::Unix::Nm do
  let(:tool) { described_class.new }
  let(:result) { {ok: true, stdout: "0000000000000000 T main\n", stderr: ""} }

  before do
    allow(tool).to receive(:execute).and_return(result)
  end

  describe ".function" do
    let(:params) { described_class.function.params }

    it "defines every param a symbol listing takes" do
      expect(params.properties.keys).to contain_exactly(
        "paths", "undefined", "external", "demangle", "dynamic", "file_name",
        "size", "numeric_sort", "portable", "timeout", "max_bytes"
      )
    end

    it "marks the paths param as required" do
      expect(params.properties[:paths]).to be_required
    end

    it "defines the flags as booleans" do
      expect(params.properties[:undefined]).to be_a(LLM::Schema::Boolean)
      expect(params.properties[:portable]).to be_a(LLM::Schema::Boolean)
    end

    it "defaults the timeout to 30 seconds" do
      expect(params.properties[:timeout].default).to eq(30)
    end
  end

  describe "#call" do
    it "lists the symbols with no flags" do
      tool.call(paths: ["foo.o"])
      expect(tool).to have_received(:execute).with(
        command: "nm",
        arguments: ["--", "foo.o"],
        timeout: 30,
        max_bytes: described_class.max_bytes
      )
    end

    it "passes the paths in the order given" do
      tool.call(paths: %w[foo.o libfoo.a])
      expect(tool).to have_received(:execute)
        .with(hash_including(arguments: ["--", "foo.o", "libfoo.a"]))
    end

    it "passes undefined as -u" do
      tool.call(paths: ["libfoo.a"], undefined: true)
      expect(tool).to have_received(:execute)
        .with(hash_including(arguments: ["-u", "--", "libfoo.a"]))
    end

    it "passes external as -g" do
      tool.call(paths: ["libfoo.a"], external: true)
      expect(tool).to have_received(:execute)
        .with(hash_including(arguments: ["-g", "--", "libfoo.a"]))
    end

    it "passes demangle as -C" do
      tool.call(paths: ["libfoo.a"], demangle: true)
      expect(tool).to have_received(:execute)
        .with(hash_including(arguments: ["-C", "--", "libfoo.a"]))
    end

    it "passes dynamic as -D" do
      tool.call(paths: ["./foo"], dynamic: true)
      expect(tool).to have_received(:execute)
        .with(hash_including(arguments: ["-D", "--", "./foo"]))
    end

    it "passes file name as -A" do
      tool.call(paths: ["foo.o"], file_name: true)
      expect(tool).to have_received(:execute)
        .with(hash_including(arguments: ["-A", "--", "foo.o"]))
    end

    it "passes size as -S" do
      tool.call(paths: ["foo.o"], size: true)
      expect(tool).to have_received(:execute)
        .with(hash_including(arguments: ["-S", "--", "foo.o"]))
    end

    it "passes numeric sort as -n" do
      tool.call(paths: ["foo.o"], numeric_sort: true)
      expect(tool).to have_received(:execute)
        .with(hash_including(arguments: ["-n", "--", "foo.o"]))
    end

    it "passes portable as -P" do
      tool.call(paths: ["foo.o"], portable: true)
      expect(tool).to have_received(:execute)
        .with(hash_including(arguments: ["-P", "--", "foo.o"]))
    end

    it "passes every flag in a fixed order" do
      arguments = ["-A", "-C", "-D", "-g", "-n", "-P", "-S", "-u", "--", "foo.o"]
      tool.call(
        paths: ["foo.o"], undefined: true, external: true, demangle: true,
        dynamic: true, file_name: true, size: true, numeric_sort: true, portable: true
      )
      expect(tool).to have_received(:execute).with(hash_including(arguments:))
    end

    it "forwards the timeout" do
      tool.call(paths: ["foo.o"], timeout: 5)
      expect(tool).to have_received(:execute).with(hash_including(timeout: 5))
    end

    it "passes the max bytes" do
      tool.call(paths: ["foo.o"], max_bytes: 100)
      expect(tool).to have_received(:execute).with(hash_including(max_bytes: 100))
    end

    it "returns the result as it is when nm succeeded" do
      expect(tool.call(paths: ["foo.o"])).to eq(result)
    end

    it "returns the result as it is when nm failed" do
      stderr = "nm: 'foo.o': No such file or directory\n"
      allow(tool).to receive(:execute).and_return({ok: false, stdout: "", stderr:})
      expect(tool.call(paths: ["foo.o"])).to eq({ok: false, stdout: "", stderr:})
    end
  end

  describe "validation" do
    it "raises when there are no paths" do
      expect { tool.call(paths: []) }
        .to raise_error("paths must be one or more files")
    end

    it "raises when a path is empty" do
      expect { tool.call(paths: [""]) }
        .to raise_error("a path can't be empty")
    end

    it "raises when a path is a dash" do
      expect { tool.call(paths: ["-"]) }
        .to raise_error("a path of '-' reads the standard input and is not supported")
    end
  end
end
