# frozen_string_literal: true

require "setup"
require "llm/tools/bsd"

RSpec.describe LLM::Tool::BSD::Truss do
  let(:tool) { described_class.new }
  let(:shell) { instance_double(LLM::Tool::Exec) }
  let(:result) { {ok: true, stdout: "", stderr: "open(3,...)\n"} }

  before do
    allow(LLM::Tool::Exec).to receive(:new).and_return(shell)
    allow(shell).to receive(:call).and_return(result)
  end

  describe ".function" do
    let(:params) { described_class.function.params }

    it "defines every param a trace takes" do
      expect(params.properties.keys).to contain_exactly(
        "command", "arguments", "pid", "follow", "count", "signals",
        "output", "string_size", "timeout", "max_bytes"
      )
    end

    it "defines follow, count and signals as booleans" do
      expect(params.properties[:follow]).to be_a(LLM::Schema::Boolean)
      expect(params.properties[:count]).to be_a(LLM::Schema::Boolean)
      expect(params.properties[:signals]).to be_a(LLM::Schema::Boolean)
    end

    it "defaults the timeout to 60 seconds" do
      expect(params.properties[:timeout].default).to eq(60)
    end
  end

  describe "#call" do
    it "traces the command with no flags" do
      tool.call(command: "./boot")
      expect(shell).to have_received(:call).with(
        command: "truss",
        arguments: ["./boot"],
        timeout: 60,
        max_bytes: LLM::Tool::Exec.max_bytes
      )
    end

    it "passes the arguments after the command" do
      tool.call(command: "./boot", arguments: ["-v", "--dry-run"])
      expect(shell).to have_received(:call)
        .with(hash_including(arguments: ["./boot", "-v", "--dry-run"]))
    end

    it "passes follow as -f" do
      tool.call(command: "./sh", follow: true)
      expect(shell).to have_received(:call)
        .with(hash_including(arguments: ["-f", "./sh"]))
    end

    it "passes count as -c" do
      tool.call(command: "./boot", count: true)
      expect(shell).to have_received(:call)
        .with(hash_including(arguments: ["-c", "./boot"]))
    end

    it "passes -S when the signals are not wanted" do
      tool.call(command: "./boot", signals: false)
      expect(shell).to have_received(:call)
        .with(hash_including(arguments: ["-S", "./boot"]))
    end

    it "passes the output as -o" do
      tool.call(command: "./boot", output: "trace.out")
      expect(shell).to have_received(:call)
        .with(hash_including(arguments: ["-o", "trace.out", "./boot"]))
    end

    it "passes the string size as -s" do
      tool.call(command: "./boot", string_size: 64)
      expect(shell).to have_received(:call)
        .with(hash_including(arguments: ["-s", "64", "./boot"]))
    end

    it "traces a pid when there is no command" do
      tool.call(pid: 34)
      expect(shell).to have_received(:call)
        .with(hash_including(arguments: ["-p", "34"]))
    end

    it "passes every argument in a fixed order" do
      arguments = ["-f", "-c", "-S", "-o", "trace.out", "-s", "64", "./boot", "-v"]
      tool.call(
        command: "./boot", arguments: ["-v"], follow: true, count: true,
        signals: false, output: "trace.out", string_size: 64
      )
      expect(shell).to have_received(:call).with(hash_including(arguments:))
    end

    it "forwards the timeout" do
      tool.call(command: "./boot", timeout: 5)
      expect(shell).to have_received(:call).with(hash_including(timeout: 5))
    end

    it "passes the max bytes" do
      tool.call(command: "./boot", max_bytes: 100)
      expect(shell).to have_received(:call).with(hash_including(max_bytes: 100))
    end

    it "returns the result as it is when the trace succeeded" do
      expect(tool.call(command: "./boot")).to eq(result)
    end

    it "returns the result as it is when the command failed" do
      stderr = "execve(0x...,0x...,0x...) ERR#2 'No such file or directory'\n"
      allow(shell).to receive(:call).and_return({ok: false, stdout: "", stderr:})
      expect(tool.call(command: "./boot")).to eq({ok: false, stdout: "", stderr:})
    end
  end

  describe "validation" do
    it "raises when there is neither a command nor a pid" do
      expect { tool.call }
        .to raise_error("a command or a pid is required")
    end

    it "raises when there is a command and a pid" do
      expect { tool.call(command: "./boot", pid: 34) }
        .to raise_error("command and pid are mutually exclusive")
    end

    it "raises when the command is empty" do
      expect { tool.call(command: "") }
        .to raise_error("a command can't be empty")
    end

    it "raises when the command begins with a dash" do
      expect { tool.call(command: "-f") }
        .to raise_error("a command can't begin with '-'")
    end

    it "raises when the pid is not a positive integer" do
      expect { tool.call(pid: 0) }
        .to raise_error("pid must be a positive integer")
    end

    it "raises when the output is empty" do
      expect { tool.call(command: "./boot", output: "") }
        .to raise_error("output can't be empty")
    end

    it "raises when the string size is not a positive integer" do
      expect { tool.call(command: "./boot", string_size: 0) }
        .to raise_error("string_size must be a positive integer")
    end
  end
end
