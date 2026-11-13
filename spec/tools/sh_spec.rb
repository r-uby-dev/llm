# frozen_string_literal: true

require "setup"
require "llm/tools/bsd"

RSpec.describe LLM::Tool::BSD::Sh do
  let(:tool) { described_class.new }
  let(:result) { {ok: true, stdout: "hi\n", stderr: ""} }

  before do
    allow(tool).to receive(:exec).and_return(result)
  end

  describe ".function" do
    let(:params) { described_class.function.params }

    it "defines every param sh takes" do
      expect(params.properties.keys).to contain_exactly(
        "script", "errexit", "nounset", "noexec", "xtrace", "verbose",
        "noclobber", "noglob", "physical", "pipefail", "timeout", "max_bytes"
      )
    end

    it "marks the script param as required" do
      expect(params.properties[:script]).to be_required
    end

    it "defines the flags as booleans" do
      expect(params.properties[:errexit]).to be_a(LLM::Schema::Boolean)
      expect(params.properties[:nounset]).to be_a(LLM::Schema::Boolean)
      expect(params.properties[:noexec]).to be_a(LLM::Schema::Boolean)
      expect(params.properties[:xtrace]).to be_a(LLM::Schema::Boolean)
      expect(params.properties[:verbose]).to be_a(LLM::Schema::Boolean)
      expect(params.properties[:noclobber]).to be_a(LLM::Schema::Boolean)
      expect(params.properties[:noglob]).to be_a(LLM::Schema::Boolean)
      expect(params.properties[:physical]).to be_a(LLM::Schema::Boolean)
      expect(params.properties[:pipefail]).to be_a(LLM::Schema::Boolean)
    end
  end

  describe "#call" do
    it "runs the script with -c and no other flag" do
      tool.call(script: "echo hi")
      expect(tool).to have_received(:exec).with(
        command: "sh",
        arguments: ["-c", "echo hi"],
        timeout: 30,
        max_bytes: described_class.max_bytes
      )
    end

    it "passes a whole script as one operand" do
      tool.call(script: "cd /usr/src && make -j8")
      expect(tool).to have_received(:exec)
        .with(hash_including(arguments: ["-c", "cd /usr/src && make -j8"]))
    end

    it "passes errexit as -e" do
      tool.call(script: "echo hi", errexit: true)
      expect(tool).to have_received(:exec)
        .with(hash_including(arguments: ["-e", "-c", "echo hi"]))
    end

    it "passes nounset as -u" do
      tool.call(script: "echo hi", nounset: true)
      expect(tool).to have_received(:exec)
        .with(hash_including(arguments: ["-u", "-c", "echo hi"]))
    end

    it "passes noexec as -n" do
      tool.call(script: "echo hi", noexec: true)
      expect(tool).to have_received(:exec)
        .with(hash_including(arguments: ["-n", "-c", "echo hi"]))
    end

    it "passes xtrace as -x" do
      tool.call(script: "echo hi", xtrace: true)
      expect(tool).to have_received(:exec)
        .with(hash_including(arguments: ["-x", "-c", "echo hi"]))
    end

    it "passes verbose as -v" do
      tool.call(script: "echo hi", verbose: true)
      expect(tool).to have_received(:exec)
        .with(hash_including(arguments: ["-v", "-c", "echo hi"]))
    end

    it "passes noclobber as -C" do
      tool.call(script: "echo hi", noclobber: true)
      expect(tool).to have_received(:exec)
        .with(hash_including(arguments: ["-C", "-c", "echo hi"]))
    end

    it "passes noglob as -f" do
      tool.call(script: "echo *", noglob: true)
      expect(tool).to have_received(:exec)
        .with(hash_including(arguments: ["-f", "-c", "echo *"]))
    end

    it "passes physical as -P" do
      tool.call(script: "pwd", physical: true)
      expect(tool).to have_received(:exec)
        .with(hash_including(arguments: ["-P", "-c", "pwd"]))
    end

    it "passes pipefail as -o pipefail, since it has no single letter" do
      tool.call(script: "a | b", pipefail: true)
      expect(tool).to have_received(:exec)
        .with(hash_including(arguments: ["-o", "pipefail", "-c", "a | b"]))
    end

    it "passes every flag in a fixed order" do
      tool.call(
        script: "echo hi", errexit: true, nounset: true, noexec: true,
        xtrace: true, verbose: true, noclobber: true, noglob: true,
        physical: true, pipefail: true
      )
      expect(tool).to have_received(:exec).with(
        hash_including(
          arguments: %w[-C -e -f -n -P -u -v -x -o pipefail -c echo\ hi]
        )
      )
    end

    it "forwards the timeout" do
      tool.call(script: "sleep 60", timeout: 1)
      expect(tool).to have_received(:exec).with(hash_including(timeout: 1))
    end

    it "passes the max bytes" do
      tool.call(script: "echo hi", max_bytes: 100)
      expect(tool).to have_received(:exec).with(hash_including(max_bytes: 100))
    end

    it "returns the result as it is" do
      expect(tool.call(script: "echo hi")).to eq(result)
    end
  end

  describe "validation" do
    it "raises when the script is empty" do
      expect { tool.call(script: "") }
        .to raise_error("script can't be empty")
    end

    it "raises when the script is only whitespace" do
      expect { tool.call(script: " \n ") }
        .to raise_error("script can't be empty")
    end

    it "raises when the script has a NUL byte" do
      expect { tool.call(script: "echo hi\0") }
        .to raise_error("a script can't contain a NUL character")
    end
  end
end
