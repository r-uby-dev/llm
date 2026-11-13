# frozen_string_literal: true

require "setup"
require "llm/tools/unix"

RSpec.describe LLM::Tool::Unix::Ls do
  let(:tool) { described_class.new }
  let(:result) { {ok: true, stdout: "a.txt\nb.txt\n", stderr: ""} }

  before do
    allow(tool).to receive(:exec).and_return(result)
  end

  describe ".function" do
    let(:params) { described_class.function.params }

    it "defines every param ls takes" do
      expect(params.properties.keys).to contain_exactly(
        "paths", "all", "almost_all", "long", "human", "classify",
        "inode", "recursive", "directory", "sort", "reverse",
        "timeout", "max_bytes"
      )
    end

    it "does not require a path" do
      expect(params.properties[:paths]).to_not be_required
    end

    it "defines the flags as booleans" do
      expect(params.properties[:all]).to be_a(LLM::Schema::Boolean)
      expect(params.properties[:almost_all]).to be_a(LLM::Schema::Boolean)
      expect(params.properties[:long]).to be_a(LLM::Schema::Boolean)
      expect(params.properties[:human]).to be_a(LLM::Schema::Boolean)
      expect(params.properties[:classify]).to be_a(LLM::Schema::Boolean)
      expect(params.properties[:inode]).to be_a(LLM::Schema::Boolean)
      expect(params.properties[:recursive]).to be_a(LLM::Schema::Boolean)
      expect(params.properties[:directory]).to be_a(LLM::Schema::Boolean)
      expect(params.properties[:reverse]).to be_a(LLM::Schema::Boolean)
    end
  end

  describe "#call" do
    it "lists the working directory with no flags" do
      tool.call
      expect(tool).to have_received(:exec).with(
        command: "ls",
        arguments: [],
        timeout: 5,
        max_bytes: described_class.max_bytes
      )
    end

    it "lists the paths in the order given, after --" do
      tool.call(paths: %w[a.txt b.txt])
      expect(tool).to have_received(:exec)
        .with(hash_including(arguments: ["--", "a.txt", "b.txt"]))
    end

    it "keeps a path that begins with a dash after --" do
      tool.call(paths: ["-n"])
      expect(tool).to have_received(:exec)
        .with(hash_including(arguments: ["--", "-n"]))
    end

    it "passes all as -a" do
      tool.call(all: true)
      expect(tool).to have_received(:exec).with(hash_including(arguments: ["-a"]))
    end

    it "passes almost_all as -A" do
      tool.call(almost_all: true)
      expect(tool).to have_received(:exec).with(hash_including(arguments: ["-A"]))
    end

    it "passes long as -l" do
      tool.call(long: true)
      expect(tool).to have_received(:exec).with(hash_including(arguments: ["-l"]))
    end

    it "passes human as -h beside -l" do
      tool.call(long: true, human: true)
      expect(tool).to have_received(:exec)
        .with(hash_including(arguments: ["-h", "-l"]))
    end

    it "passes classify as -F" do
      tool.call(classify: true)
      expect(tool).to have_received(:exec).with(hash_including(arguments: ["-F"]))
    end

    it "passes inode as -i" do
      tool.call(inode: true)
      expect(tool).to have_received(:exec).with(hash_including(arguments: ["-i"]))
    end

    it "passes recursive as -R" do
      tool.call(recursive: true)
      expect(tool).to have_received(:exec).with(hash_including(arguments: ["-R"]))
    end

    it "passes directory as -d" do
      tool.call(directory: true)
      expect(tool).to have_received(:exec).with(hash_including(arguments: ["-d"]))
    end

    it "passes reverse as -r" do
      tool.call(reverse: true)
      expect(tool).to have_received(:exec).with(hash_including(arguments: ["-r"]))
    end

    it "passes time as -t" do
      tool.call(sort: "time")
      expect(tool).to have_received(:exec).with(hash_including(arguments: ["-t"]))
    end

    it "passes size as -S" do
      tool.call(sort: "size")
      expect(tool).to have_received(:exec).with(hash_including(arguments: ["-S"]))
    end

    it "passes natural as -v" do
      tool.call(sort: "natural")
      expect(tool).to have_received(:exec).with(hash_including(arguments: ["-v"]))
    end

    it "passes none as -f" do
      tool.call(sort: "none")
      expect(tool).to have_received(:exec).with(hash_including(arguments: ["-f"]))
    end

    it "passes every flag in a fixed order" do
      tool.call(
        paths: ["a.txt"], all: true, almost_all: true, long: true, human: true,
        classify: true, inode: true, recursive: true, directory: true,
        sort: "size", reverse: true
      )
      expect(tool).to have_received(:exec).with(
        hash_including(arguments: %w[-A -F -R -a -d -h -i -l -S -r] + ["--", "a.txt"])
      )
    end

    it "forwards the timeout" do
      tool.call(timeout: 9)
      expect(tool).to have_received(:exec).with(hash_including(timeout: 9))
    end

    it "passes the max bytes" do
      tool.call(max_bytes: 100)
      expect(tool).to have_received(:exec).with(hash_including(max_bytes: 100))
    end

    it "returns the result as it is" do
      expect(tool.call).to eq(result)
    end
  end

  describe "validation" do
    it "raises when a path is empty" do
      expect { tool.call(paths: [""]) }
        .to raise_error("a path can't be empty")
    end

    it "raises when the sort order is unknown" do
      expect { tool.call(sort: "mtime") }
        .to raise_error("sort must be one of: name, time, size, natural, none")
    end
  end
end
