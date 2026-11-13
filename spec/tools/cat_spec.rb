# frozen_string_literal: true

require "setup"
require "llm/tools/unix"

RSpec.describe LLM::Tool::Unix::Cat do
  let(:tool) { described_class.new }
  let(:shell) { instance_double(LLM::Tool::Exec) }
  let(:result) { {ok: true, stdout: "a\nb\n", stderr: ""} }

  before do
    allow(LLM::Tool::Exec).to receive(:new).and_return(shell)
    allow(shell).to receive(:call).and_return(result)
  end

  describe ".function" do
    let(:params) { described_class.function.params }

    it "defines every param cat takes" do
      expect(params.properties.keys).to contain_exactly(
        "paths", "number", "squeeze_blank", "show_ends", "show_tabs",
        "show_nonprinting", "timeout", "max_bytes"
      )
    end

    it "requires the paths" do
      expect(params.required).to eq(%w[paths])
    end

    it "defines the flags as booleans" do
      expect(params.properties[:number]).to be_a(LLM::Schema::Boolean)
      expect(params.properties[:squeeze_blank]).to be_a(LLM::Schema::Boolean)
      expect(params.properties[:show_ends]).to be_a(LLM::Schema::Boolean)
      expect(params.properties[:show_tabs]).to be_a(LLM::Schema::Boolean)
      expect(params.properties[:show_nonprinting]).to be_a(LLM::Schema::Boolean)
    end
  end

  describe "#call" do
    it "prints the path with no flags" do
      tool.call(paths: ["a.txt"])
      expect(shell).to have_received(:call).with(
        command: "cat",
        arguments: ["--", "a.txt"],
        timeout: 5,
        max_bytes: LLM::Tool::Exec.max_bytes
      )
    end

    it "prints the paths in the order given" do
      tool.call(paths: %w[a.txt b.txt c.txt])
      expect(shell).to have_received(:call)
        .with(hash_including(arguments: ["--", "a.txt", "b.txt", "c.txt"]))
    end

    it "passes number as -n" do
      tool.call(paths: ["a.txt"], number: true)
      expect(shell).to have_received(:call)
        .with(hash_including(arguments: ["-n", "--", "a.txt"]))
    end

    it "passes squeeze_blank as -s" do
      tool.call(paths: ["a.txt"], squeeze_blank: true)
      expect(shell).to have_received(:call)
        .with(hash_including(arguments: ["-s", "--", "a.txt"]))
    end

    it "passes show_ends as -E" do
      tool.call(paths: ["a.txt"], show_ends: true)
      expect(shell).to have_received(:call)
        .with(hash_including(arguments: ["-E", "--", "a.txt"]))
    end

    it "passes show_tabs as -T" do
      tool.call(paths: ["a.txt"], show_tabs: true)
      expect(shell).to have_received(:call)
        .with(hash_including(arguments: ["-T", "--", "a.txt"]))
    end

    it "passes show_nonprinting as -v" do
      tool.call(paths: ["a.txt"], show_nonprinting: true)
      expect(shell).to have_received(:call)
        .with(hash_including(arguments: ["-v", "--", "a.txt"]))
    end

    it "passes every flag in a fixed order" do
      tool.call(
        paths: ["a.txt"], number: true, squeeze_blank: true, show_ends: true,
        show_tabs: true, show_nonprinting: true
      )
      expect(shell).to have_received(:call)
        .with(hash_including(arguments: ["-E", "-n", "-s", "-T", "-v", "--", "a.txt"]))
    end

    it "passes a path that begins with a dash after --" do
      tool.call(paths: ["-n"])
      expect(shell).to have_received(:call)
        .with(hash_including(arguments: ["--", "-n"]))
    end

    it "forwards the timeout" do
      tool.call(paths: ["a.txt"], timeout: 9)
      expect(shell).to have_received(:call).with(hash_including(timeout: 9))
    end

    it "passes the max bytes" do
      tool.call(paths: ["a.txt"], max_bytes: 100)
      expect(shell).to have_received(:call).with(hash_including(max_bytes: 100))
    end

    it "returns the result as it is when cat succeeded" do
      expect(tool.call(paths: ["a.txt"])).to eq(result)
    end

    it "returns the result as it is when cat failed" do
      allow(shell).to receive(:call)
        .and_return({ok: false, stdout: "", stderr: "cat: nope.txt: No such file or directory\n"})
      expect(tool.call(paths: ["nope.txt"])).to eq(
        {ok: false, stdout: "", stderr: "cat: nope.txt: No such file or directory\n"}
      )
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
        .to raise_error("a path can't be '-' (that reads standard input)")
    end
  end
end
