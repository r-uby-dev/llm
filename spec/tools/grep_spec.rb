# frozen_string_literal: true

require "setup"
require "llm/tools/unix"

RSpec.describe LLM::Tool::Unix::Grep do
  let(:tool) { described_class.new }
  let(:result) { {ok: true, stdout: "a.txt:hi\n", stderr: ""} }

  before do
    allow(tool).to receive(:exec).and_return(result)
  end

  describe ".function" do
    let(:params) { described_class.function.params }

    it "defines every param grep takes" do
      expect(params.properties.keys).to contain_exactly(
        "pattern", "paths", "extended", "fixed", "ignore_case", "invert",
        "line", "count", "files_with_matches", "line_number",
        "byte_offset", "quiet", "no_messages", "timeout", "max_bytes"
      )
    end

    it "marks the pattern and the paths as required" do
      expect(params.properties[:pattern]).to be_required
      expect(params.properties[:paths]).to be_required
    end

    it "defines the flags as booleans" do
      expect(params.properties[:extended]).to be_a(LLM::Schema::Boolean)
      expect(params.properties[:fixed]).to be_a(LLM::Schema::Boolean)
      expect(params.properties[:ignore_case]).to be_a(LLM::Schema::Boolean)
      expect(params.properties[:invert]).to be_a(LLM::Schema::Boolean)
      expect(params.properties[:line]).to be_a(LLM::Schema::Boolean)
      expect(params.properties[:count]).to be_a(LLM::Schema::Boolean)
      expect(params.properties[:files_with_matches]).to be_a(LLM::Schema::Boolean)
      expect(params.properties[:line_number]).to be_a(LLM::Schema::Boolean)
      expect(params.properties[:byte_offset]).to be_a(LLM::Schema::Boolean)
      expect(params.properties[:quiet]).to be_a(LLM::Schema::Boolean)
      expect(params.properties[:no_messages]).to be_a(LLM::Schema::Boolean)
    end
  end

  describe "#call" do
    it "passes the pattern to -e and the paths after --" do
      tool.call(pattern: "hi", paths: ["a.txt"])
      expect(tool).to have_received(:exec).with(
        command: "grep",
        arguments: ["-e", "hi", "--", "a.txt"],
        timeout: 30,
        max_bytes: described_class.max_bytes
      )
    end

    it "keeps a pattern that begins with a dash as a pattern" do
      tool.call(pattern: "-v", paths: ["a.txt"])
      expect(tool).to have_received(:exec)
        .with(hash_including(arguments: ["-e", "-v", "--", "a.txt"]))
    end

    it "keeps a path that begins with a dash after --" do
      tool.call(pattern: "hi", paths: ["-n"])
      expect(tool).to have_received(:exec)
        .with(hash_including(arguments: ["-e", "hi", "--", "-n"]))
    end

    it "passes extended as -E" do
      tool.call(pattern: "h+", paths: ["a.txt"], extended: true)
      expect(tool).to have_received(:exec)
        .with(hash_including(arguments: ["-E", "-e", "h+", "--", "a.txt"]))
    end

    it "passes fixed as -F" do
      tool.call(pattern: "h+", paths: ["a.txt"], fixed: true)
      expect(tool).to have_received(:exec)
        .with(hash_including(arguments: ["-F", "-e", "h+", "--", "a.txt"]))
    end

    it "passes ignore_case as -i" do
      tool.call(pattern: "hi", paths: ["a.txt"], ignore_case: true)
      expect(tool).to have_received(:exec)
        .with(hash_including(arguments: ["-i", "-e", "hi", "--", "a.txt"]))
    end

    it "passes invert as -v" do
      tool.call(pattern: "hi", paths: ["a.txt"], invert: true)
      expect(tool).to have_received(:exec)
        .with(hash_including(arguments: ["-v", "-e", "hi", "--", "a.txt"]))
    end

    it "passes line as -x" do
      tool.call(pattern: "hi", paths: ["a.txt"], line: true)
      expect(tool).to have_received(:exec)
        .with(hash_including(arguments: ["-x", "-e", "hi", "--", "a.txt"]))
    end

    it "passes count as -c" do
      tool.call(pattern: "hi", paths: ["a.txt"], count: true)
      expect(tool).to have_received(:exec)
        .with(hash_including(arguments: ["-c", "-e", "hi", "--", "a.txt"]))
    end

    it "passes files_with_matches as -l" do
      tool.call(pattern: "hi", paths: ["a.txt"], files_with_matches: true)
      expect(tool).to have_received(:exec)
        .with(hash_including(arguments: ["-l", "-e", "hi", "--", "a.txt"]))
    end

    it "passes line_number as -n" do
      tool.call(pattern: "hi", paths: ["a.txt"], line_number: true)
      expect(tool).to have_received(:exec)
        .with(hash_including(arguments: ["-n", "-e", "hi", "--", "a.txt"]))
    end

    it "passes byte_offset as -b" do
      tool.call(pattern: "hi", paths: ["a.txt"], byte_offset: true)
      expect(tool).to have_received(:exec)
        .with(hash_including(arguments: ["-b", "-e", "hi", "--", "a.txt"]))
    end

    it "passes quiet as -q" do
      tool.call(pattern: "hi", paths: ["a.txt"], quiet: true)
      expect(tool).to have_received(:exec)
        .with(hash_including(arguments: ["-q", "-e", "hi", "--", "a.txt"]))
    end

    it "passes no_messages as -s" do
      tool.call(pattern: "hi", paths: ["a.txt"], no_messages: true)
      expect(tool).to have_received(:exec)
        .with(hash_including(arguments: ["-s", "-e", "hi", "--", "a.txt"]))
    end

    it "passes every flag in a fixed order" do
      tool.call(
        pattern: "hi", paths: ["a.txt"], extended: true, byte_offset: true,
        count: true, ignore_case: true, files_with_matches: true,
        line_number: true, quiet: true, no_messages: true, invert: true,
        line: true
      )
      expect(tool).to have_received(:exec).with(
        hash_including(
          arguments: %w[-E -b -c -i -l -n -q -s -v -x -e hi -- a.txt]
        )
      )
    end

    it "searches several files" do
      tool.call(pattern: "hi", paths: %w[a.txt b.txt])
      expect(tool).to have_received(:exec)
        .with(hash_including(arguments: ["-e", "hi", "--", "a.txt", "b.txt"]))
    end

    it "forwards the timeout" do
      tool.call(pattern: "hi", paths: ["a.txt"], timeout: 9)
      expect(tool).to have_received(:exec).with(hash_including(timeout: 9))
    end

    it "passes the max bytes" do
      tool.call(pattern: "hi", paths: ["a.txt"], max_bytes: 100)
      expect(tool).to have_received(:exec).with(hash_including(max_bytes: 100))
    end

    it "returns the result as it is" do
      expect(tool.call(pattern: "hi", paths: ["a.txt"])).to eq(result)
    end
  end

  describe "validation" do
    it "raises when the pattern is empty" do
      expect { tool.call(pattern: "", paths: ["a.txt"]) }
        .to raise_error("pattern can't be empty")
    end

    it "raises when extended and fixed are both set" do
      expect { tool.call(pattern: "hi", paths: ["a.txt"], extended: true, fixed: true) }
        .to raise_error("extended and fixed can't both be set")
    end

    it "raises when there is no path" do
      expect { tool.call(pattern: "hi", paths: []) }
        .to raise_error("at least one path is required")
    end

    it "raises when a path is empty" do
      expect { tool.call(pattern: "hi", paths: [""]) }
        .to raise_error("a path can't be empty")
    end
  end
end
