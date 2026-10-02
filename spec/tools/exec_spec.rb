# frozen_string_literal: true

require "setup"
require "llm/tools/exec"

RSpec.describe LLM::Tool::Exec do
  let(:tool) { described_class.new }
  let(:command) do
    instance_double(Test::Command, running?: false, success?: true, stdout: "hi\n", stderr: "", :not_found? => false)
  end

  describe ".function" do
    let(:params) { described_class.function.params }

    it "defines the arguments param" do
      expect(params.properties[:arguments]).to be_a(LLM::Schema::Array)
    end

    it "marks the arguments param as required" do
      expect(params.properties[:arguments]).to be_required
    end

    it "has a timeout parameter with a default" do
      expect(params.properties[:timeout].default).to eq(60)
    end
  end

  describe "#call" do
    it "raises when the command exceeds the timeout" do
      expect { tool.call(arguments: ["sleep", "10"], timeout: 0.1) }.to raise_error(
        RuntimeError,
        "command timed out after 0.1s"
      )
    end

    context "when given arguments" do
      before do
        allow(command).to receive(:env).and_return(command)
        allow(command).to receive(:arguments).and_return(command)
        allow(command).to receive(:spawn).and_return(command)
        allow(command).to receive(:limit).and_return(command)
        allow(LLM::Tool::Exec::Command).to receive(:new).and_return(command)
        tool.call(arguments: ["echo", "hi"])
      end

      it "limits stdout and stderr by max_bytes" do
        expect(command).to have_received(:limit).with(
          stdout: LLM::Tool::Exec.max_bytes,
          stderr: LLM::Tool::Exec.max_bytes
        )
      end

      it "passes the arguments to the command" do
        expect(command).to have_received(:arguments).with("hi")
      end

      it "passes an empty env by default" do
        expect(command).to have_received(:env).with({})
      end

      it "returns the command output" do
        expect(tool.call(arguments: ["echo", "hi"])).to eq(
          ok: true, stdout: "hi\n", stderr: "", duration: "0.0 seconds"
        )
      end
    end

    ##
    # The race a real `echo` lost: `running?` is false before the command has
    # been reaped, so a wait that trusts it alone leaves, and `ok` is read from
    # a status that does not exist yet. The double answers nil once, which is
    # what the second question is for.
    context "when the command has not been reaped yet" do
      let(:result) { tool.call(arguments: ["echo", "hi"]) }

      before do
        allow(command).to receive(:env).and_return(command)
        allow(command).to receive(:arguments).and_return(command)
        allow(command).to receive(:spawn).and_return(command)
        allow(command).to receive(:limit).and_return(command)
        allow(LLM::Tool::Exec::Command).to receive(:new).and_return(command)
        allow(command).to receive(:success?).and_return(nil, true)
      end

      it "waits for a status rather than reading nil" do
        expect(result).to include(ok: true)
      end
    end

    context "when constructed with env" do
      before do
        allow(command).to receive(:env).and_return(command)
        allow(command).to receive(:arguments).and_return(command)
        allow(command).to receive(:spawn).and_return(command)
        allow(command).to receive(:limit).and_return(command)
        allow(LLM::Tool::Exec::Command).to receive(:new).and_return(command)
        described_class.new(env: {"FOO" => "bar"}).call(arguments: ["echo", "hi"])
      end

      it "passes the env to the command" do
        expect(command).to have_received(:env).with({"FOO" => "bar"})
      end
    end
  end

  describe "when spawning a real command" do
    let(:arguments) { ["echo", ""] }
    let(:result) { tool.call(arguments:) }

    context "given echo" do
      let(:arguments) { ["echo", "hello world"] }

      it "captures fixed stdout" do
        expect(result).to include(ok: true, stdout: "hello world\n", stderr: "")
      end

      it "reports how long the command ran" do
        expect(result[:duration]).to match(/\A\d+\.\d seconds\z/)
      end

      it "reports a sub-second command as a fraction" do
        expect(result[:duration].to_f).to be < 1
      end
    end

    context "given sleep" do
      let(:arguments) { ["sleep", "1"] }
      let(:seconds) { result[:duration].to_f }

      it "measures how long the command ran" do
        expect(seconds).to be >= 1
      end
    end

    context "given printf" do
      let(:arguments) { ["printf", "no-newline"] }

      it "captures fixed stdout" do
        expect(result[:stdout]).to eq("no-newline")
      end

      it "returns an empty stderr" do
        expect(result[:stderr]).to eq("")
      end
    end

    context "given sh" do
      let(:arguments) { ["sh", "-c", "echo oops >&2"] }

      it "captures fixed stderr" do
        expect(result).to include(ok: true, stdout: "", stderr: "oops\n")
      end
    end

    context "given false" do
      let(:arguments) { ["false"] }

      it "reports a failing command" do
        expect(result[:ok]).to be(false)
      end

      it "returns an empty stdout" do
        expect(result[:stdout]).to eq("")
      end
    end

    context "when the command is not found" do
      let(:arguments) { ["definitely-not-a-real-command-xyz"] }

      it "reports ok as false" do
        expect(result[:ok]).to be(false)
      end

      it "reports the error message" do
        expect(result[:error]).to include(arguments[0])
      end
    end

    context "when given env" do
      let(:tool) { described_class.new(env: {"EXEC_SPEC_FOO" => "bar"}) }
      let(:arguments) { ["sh", "-c", "printf %s \"$EXEC_SPEC_FOO\""] }

      it "sets environment for the spawned command" do
        expect(result).to include(ok: true, stdout: "bar", stderr: "")
      end
    end

    context "when given a byte limit" do
      let(:arguments) { [RbConfig.ruby, "-e", "STDOUT.write('x' * 1000)"] }
      let(:result) { tool.call(arguments:, max_bytes: 16) }

      it "caps stdout at max_bytes" do
        expect(result[:stdout]).to eq("x" * 16)
      end

      it "returns an empty stderr" do
        expect(result[:stderr]).to eq("")
      end
    end
  end
end
