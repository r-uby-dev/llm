# frozen_string_literal: true

require "setup"
require "llm/tools/unix"

RSpec.describe LLM::Tool::Unix::Apropos do
  let(:tool) { described_class.new }
  let(:result) {
    {ok: true, stdout: "printf(3) - formatted output conversion\n", stderr: ""}
  }

  before do
    allow(tool).to receive(:exec).and_return(result)
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

    it "defaults max_bytes to the max_bytes of the tool" do
      expect(params.properties[:max_bytes].default).to eq(described_class.max_bytes)
    end
  end

  describe "#call" do
    it "runs apropos through #exec" do
      tool.call(keywords: %w[printf])
      expect(tool).to have_received(:exec).with(
        command: "apropos",
        arguments: ["--", "printf"],
        env: an_instance_of(::Hash),
        timeout: 5,
        max_bytes: described_class.max_bytes
      )
    end

    it "returns the result" do
      expect(tool.call(keywords: %w[printf])).to eq(result)
    end

    it "passes each keyword as a term of its own" do
      tool.call(keywords: %w[set uid])
      expect(tool).to have_received(:exec)
        .with(hash_including(arguments: ["--", "set", "uid"]))
    end

    it "passes the section as -s before the separator" do
      tool.call(keywords: %w[printf], section: 3)
      expect(tool).to have_received(:exec)
        .with(hash_including(arguments: ["-s", "3", "--", "printf"]))
    end

    it "forwards the timeout" do
      tool.call(keywords: %w[printf], timeout: 9)
      expect(tool).to have_received(:exec).with(hash_including(timeout: 9))
    end

    it "passes the max bytes" do
      tool.call(keywords: %w[printf], max_bytes: 100)
      expect(tool).to have_received(:exec).with(hash_including(max_bytes: 100))
    end
  end

  describe "environment" do
    before do
      allow(ENV).to receive(:[]).and_call_original
    end

    it "passes an empty environment when $MANPATH is not set" do
      allow(ENV).to receive(:[]).with("MANPATH").and_return(nil)
      tool.call(keywords: %w[printf])
      expect(tool).to have_received(:exec).with(hash_including(env: {}))
    end

    it "forwards $MANPATH when it is set" do
      allow(ENV).to receive(:[]).with("MANPATH").and_return("/opt/man")
      tool.call(keywords: %w[printf])
      expect(tool).to have_received(:exec)
        .with(hash_including(env: {"MANPATH" => "/opt/man"}))
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
