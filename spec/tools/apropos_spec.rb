# frozen_string_literal: true

require "setup"
require "llm/tools/apropos"
require "llm/tools/exec"

RSpec.describe LLM::Tool::Apropos do
  let(:tool) { described_class.new }
  let(:shell) { instance_double(LLM::Tool::Exec) }
  let(:result) {
    {ok: true, stdout: "printf(3) - formatted output conversion\n", stderr: ""}
  }

  before do
    allow(LLM::Tool::Exec).to receive(:new).and_return(shell)
  end

  describe ".function" do
    let(:params) { described_class.function.params }

    it "defines the keywords param" do
      expect(params.properties[:keywords]).to be_a(LLM::Schema::Array)
    end

    it "marks the keywords param as required" do
      expect(params.properties[:keywords]).to be_required
    end

    it "defines the keywords, section, timeout and max_bytes params" do
      expect(params.properties.keys).to contain_exactly(
        "keywords", "section", "timeout", "max_bytes"
      )
    end
  end

  describe "#call" do
    before do
      allow(shell).to receive(:call).and_return(result)
    end

    it "runs apropos through the exec tool" do
      tool.call(keywords: %w[printf])
      expect(shell).to have_received(:call).with(
        command: "apropos",
        arguments: ["--", "printf"],
        timeout: 5,
        max_bytes: LLM::Tool::Exec.max_bytes
      )
    end

    it "returns the exec result" do
      expect(tool.call(keywords: %w[printf])).to eq(result)
    end

    it "passes each keyword as a term of its own" do
      tool.call(keywords: %w[set uid])
      expect(shell).to have_received(:call)
        .with(hash_including(arguments: ["--", "set", "uid"]))
    end

    it "passes the section as -s before the separator" do
      tool.call(keywords: %w[printf], section: 3)
      expect(shell).to have_received(:call)
        .with(hash_including(arguments: ["-s", "3", "--", "printf"]))
    end

    it "forwards the timeout" do
      tool.call(keywords: %w[printf], timeout: 9)
      expect(shell).to have_received(:call).with(hash_including(timeout: 9))
    end

    it "passes the max bytes" do
      tool.call(keywords: %w[printf], max_bytes: 100)
      expect(shell).to have_received(:call).with(hash_including(max_bytes: 100))
    end
  end

  describe "environment" do
    before do
      allow(shell).to receive(:call).and_return(result)
      allow(ENV).to receive(:[]).and_call_original
    end

    it "passes an empty environment when $MANPATH is not set" do
      allow(ENV).to receive(:[]).with("MANPATH").and_return(nil)
      tool.call(keywords: %w[printf])
      expect(LLM::Tool::Exec).to have_received(:new).with(env: {})
    end

    it "forwards $MANPATH when it is set" do
      allow(ENV).to receive(:[]).with("MANPATH").and_return("/opt/man")
      tool.call(keywords: %w[printf])
      expect(LLM::Tool::Exec).to have_received(:new).with(env: {"MANPATH" => "/opt/man"})
    end
  end

  describe "validation" do
    it "raises when there are no keywords" do
      expect { tool.call(keywords: []) }
        .to raise_error("keywords must be one or more non-empty keywords")
    end

    it "raises when a keyword is empty" do
      expect { tool.call(keywords: ["printf", ""]) }
        .to raise_error("keywords must be one or more non-empty keywords")
    end

    it "raises when the section is not a positive integer" do
      expect { tool.call(keywords: %w[printf], section: 0) }
        .to raise_error("section must be a positive integer")
    end
  end
end
