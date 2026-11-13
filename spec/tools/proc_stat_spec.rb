# frozen_string_literal: true

require "setup"
require "llm/tools/bsd"

RSpec.describe LLM::Tool::BSD::ProcStat do
  let(:tool) { described_class.new }
  let(:result) { {ok: true, stdout: " PID COMM\n  1 init\n", stderr: ""} }

  before do
    allow(tool).to receive(:exec).and_return(result)
  end

  describe ".function" do
    let(:params) { described_class.function.params }

    it "defines every param a query takes" do
      expect(params.properties.keys).to contain_exactly(
        "command", "pids", "all", "headers", "capabilities",
        "signal_numbers", "per_thread", "timeout", "max_bytes"
      )
    end

    it "defines the flags as booleans" do
      expect(params.properties[:all]).to be_a(LLM::Schema::Boolean)
      expect(params.properties[:headers]).to be_a(LLM::Schema::Boolean)
      expect(params.properties[:capabilities]).to be_a(LLM::Schema::Boolean)
      expect(params.properties[:signal_numbers]).to be_a(LLM::Schema::Boolean)
      expect(params.properties[:per_thread]).to be_a(LLM::Schema::Boolean)
    end

    it "constrains the command to the subcommands it exposes" do
      expect(params.properties[:command].enum).to eq(described_class::COMMANDS.keys)
    end

    it "defaults the command to basic and the timeout to 30 seconds" do
      expect(params.properties[:command].default).to eq("basic")
      expect(params.properties[:timeout].default).to eq(30)
    end
  end

  describe "#call" do
    it "prints the basic information with no flag" do
      tool.call(pids: [1])
      expect(tool).to have_received(:exec).with(
        command: "procstat",
        arguments: ["1"],
        timeout: 30,
        max_bytes: described_class.max_bytes
      )
    end

    it "passes args as -c" do
      tool.call(command: "args", pids: [1])
      expect(tool).to have_received(:exec)
        .with(hash_including(arguments: ["-c", "1"]))
    end

    it "passes binary as -b" do
      tool.call(command: "binary", pids: [1])
      expect(tool).to have_received(:exec)
        .with(hash_including(arguments: ["-b", "1"]))
    end

    it "passes credentials as -s" do
      tool.call(command: "credentials", pids: [1])
      expect(tool).to have_received(:exec)
        .with(hash_including(arguments: ["-s", "1"]))
    end

    it "passes files as -f" do
      tool.call(command: "files", pids: [1])
      expect(tool).to have_received(:exec)
        .with(hash_including(arguments: ["-f", "1"]))
    end

    it "passes vm as -v" do
      tool.call(command: "vm", pids: [1])
      expect(tool).to have_received(:exec)
        .with(hash_including(arguments: ["-v", "1"]))
    end

    it "passes cpuset as -S" do
      tool.call(command: "cpuset", pids: [1])
      expect(tool).to have_received(:exec)
        .with(hash_including(arguments: ["-S", "1"]))
    end

    it "passes kstack as -k" do
      tool.call(command: "kstack", pids: [1])
      expect(tool).to have_received(:exec)
        .with(hash_including(arguments: ["-k", "1"]))
    end

    it "passes the pids in the order given" do
      tool.call(pids: [1, 42, 7])
      expect(tool).to have_received(:exec)
        .with(hash_including(arguments: ["1", "42", "7"]))
    end

    it "passes all as -a" do
      tool.call(command: "files", all: true)
      expect(tool).to have_received(:exec)
        .with(hash_including(arguments: ["-a", "-f"]))
    end

    it "passes -h when the headers are not wanted" do
      tool.call(command: "threads", pids: [1], headers: false)
      expect(tool).to have_received(:exec)
        .with(hash_including(arguments: ["-h", "-t", "1"]))
    end

    it "passes capabilities as -C, ahead of the subcommand" do
      tool.call(command: "files", pids: [1], capabilities: true)
      expect(tool).to have_received(:exec)
        .with(hash_including(arguments: ["-C", "-f", "1"]))
    end

    it "passes signal_numbers as -n" do
      tool.call(command: "signals", pids: [1], signal_numbers: true)
      expect(tool).to have_received(:exec)
        .with(hash_including(arguments: ["-n", "-i", "1"]))
    end

    it "passes per_thread as -H" do
      tool.call(command: "rusage", pids: [1], per_thread: true)
      expect(tool).to have_received(:exec)
        .with(hash_including(arguments: ["-H", "-r", "1"]))
    end

    it "passes every argument in a fixed order" do
      tool.call(command: "files", pids: [1, 42], headers: false, capabilities: true)
      expect(tool).to have_received(:exec).with(
        hash_including(arguments: ["-h", "-C", "-f", "1", "42"])
      )
    end

    it "forwards the timeout" do
      tool.call(pids: [1], timeout: 5)
      expect(tool).to have_received(:exec).with(hash_including(timeout: 5))
    end

    it "passes the max bytes" do
      tool.call(pids: [1], max_bytes: 100)
      expect(tool).to have_received(:exec).with(hash_including(max_bytes: 100))
    end

    it "returns the result as it is" do
      expect(tool.call(pids: [1])).to eq(result)
    end

    it "returns the result as it is when procstat failed" do
      stderr = "procstat: "
      allow(tool).to receive(:exec).and_return({ok: false, stdout: "", stderr:})
      expect(tool.call(pids: [999999])).to eq({ok: false, stdout: "", stderr:})
    end
  end

  describe "validation" do
    it "raises when the command is unknown" do
      expect { tool.call(command: "lsof", pids: [1]) }
        .to raise_error("command must be one of: basic, args, binary, credentials, " \
                        "environment, files, signals, tsignals, threads, vm, rlimit, " \
                        "rusage, auxv, cpuset, kstack")
    end

    it "raises when there is neither a pid nor all" do
      expect { tool.call }
        .to raise_error("a pid or all is required")
    end

    it "raises when there is all and a pid" do
      expect { tool.call(all: true, pids: [1]) }
        .to raise_error("all and pids are mutually exclusive")
    end

    it "raises when a pid is not a positive integer" do
      expect { tool.call(pids: [0]) }
        .to raise_error("a pid must be a positive integer")
    end

    it "raises when capabilities is given to a subcommand that has no such flag" do
      expect { tool.call(command: "vm", pids: [1], capabilities: true) }
        .to raise_error("capabilities needs the files command")
    end

    it "raises when signal_numbers is given to a subcommand that has no such flag" do
      expect { tool.call(command: "files", pids: [1], signal_numbers: true) }
        .to raise_error("signal_numbers needs the signals or tsignals command")
    end

    it "raises when per_thread is given to a subcommand that has no such flag" do
      expect { tool.call(command: "vm", pids: [1], per_thread: true) }
        .to raise_error("per_thread needs the rusage command")
    end
  end
end
