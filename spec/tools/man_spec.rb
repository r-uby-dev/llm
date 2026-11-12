# frozen_string_literal: true

require "setup"
require "llm/tools/unix"

RSpec.describe LLM::Tool::Unix::Man do
  let(:tool) { described_class.new }
  let(:shell) { instance_double(LLM::Tool::Exec) }
  let(:result) { {ok: true, stdout: "PRINTF(3)\n", stderr: ""} }

  before do
    allow(LLM::Tool::Exec).to receive(:new).and_return(shell)
  end

  describe ".function" do
    let(:params) { described_class.function.params }

    it "defines the name param" do
      expect(params.properties[:name]).to be_a(LLM::Schema::String)
    end

    it "marks the name param as required" do
      expect(params.properties[:name]).to be_required
    end

    it "defines the name, section, timeout and max_bytes params" do
      expect(params.properties.keys).to contain_exactly(
        "name", "section", "timeout", "max_bytes"
      )
    end
  end

  describe "#call" do
    before do
      allow(shell).to receive(:call).and_return(result)
    end

    it "runs man through the exec tool" do
      tool.call(name: "printf")
      expect(shell).to have_received(:call).with(
        command: "man",
        arguments: ["-P", "cat", "printf"],
        timeout: 5,
        max_bytes: LLM::Tool::Exec.max_bytes
      )
    end

    it "returns the exec result" do
      expect(tool.call(name: "printf")).to eq(result)
    end

    it "passes the section before the name" do
      tool.call(name: "printf", section: 3)
      expect(shell).to have_received(:call)
        .with(hash_including(arguments: ["-P", "cat", "3", "printf"]))
    end

    it "forwards the timeout" do
      tool.call(name: "printf", timeout: 9)
      expect(shell).to have_received(:call).with(hash_including(timeout: 9))
    end

    it "passes the max bytes" do
      tool.call(name: "printf", max_bytes: 100)
      expect(shell).to have_received(:call).with(hash_including(max_bytes: 100))
    end

    it "collapses the overstrikes of a bold and an underlined character" do
      allow(shell).to receive(:call)
        .and_return({ok: true, stdout: "N\bNA\bAM\bME\bE\n", stderr: ""})
      expect(tool.call(name: "printf")).to eq(
        {ok: true, stdout: "NAME\n", stderr: ""}
      )
    end

    it "leaves the result alone when the command failed" do
      allow(shell).to receive(:call)
        .and_return({ok: false, stdout: "", stderr: "no manual entry\n"})
      expect(tool.call(name: "nope")).to eq(
        {ok: false, stdout: "", stderr: "no manual entry\n"}
      )
    end
  end

  describe "environment" do
    before do
      allow(shell).to receive(:call).and_return(result)
      allow(ENV).to receive(:[]).and_call_original
    end

    it "passes an empty environment when $MANPATH is not set" do
      allow(ENV).to receive(:[]).with("MANPATH").and_return(nil)
      tool.call(name: "printf")
      expect(LLM::Tool::Exec).to have_received(:new).with(env: {})
    end

    it "forwards $MANPATH when it is set" do
      allow(ENV).to receive(:[]).with("MANPATH").and_return("/opt/man")
      tool.call(name: "printf")
      expect(LLM::Tool::Exec).to have_received(:new).with(env: {"MANPATH" => "/opt/man"})
    end
  end

  describe "validation" do
    it "raises when the name is empty" do
      expect { tool.call(name: "") }
        .to raise_error("name must be the name of a manual page (eg 'printf')")
    end

    it "raises when the name is a path" do
      expect { tool.call(name: "../etc/passwd") }
        .to raise_error("name must be the name of a manual page (eg 'printf')")
    end

    it "raises when the section is not a positive integer" do
      expect { tool.call(name: "printf", section: 0) }
        .to raise_error("section must be a positive integer")
    end
  end
end
