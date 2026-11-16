# frozen_string_literal: true

require "setup"
require "llm/tools/unix"

RSpec.describe LLM::Tool::Unix::HonggFuzz do
  let(:tool) { described_class.new }
  let(:result) { {ok: true, stdout: "", stderr: ""} }

  before do
    allow(tool).to receive(:exec).and_return(result)
  end

  describe ".function" do
    let(:params) { described_class.function.params }

    it "defines every param the tool takes" do
      expect(params.properties.keys).to contain_exactly(
        "command", "arguments", "input", "workspace", "stdin", "threads", "iterations",
        "child_timeout", "max_file_size", "extension", "wordlist", "blacklist", "mutator",
        "flip_rate", "save_all", "nullify_stdio", "plain", "sancov", "debug_level", "report",
        "logfile", "environment", "clear_environment", "memory_limit", "timeout", "max_bytes"
      )
    end

    it "marks the command param as required" do
      expect(params.properties[:command]).to be_required
    end

    it "offers the input file placeholder as the default argument" do
      expect(params.properties[:arguments].default).to eq([described_class::FILE])
    end

    it "constrains the debug level to the levels honggfuzz has" do
      expect(params.properties[:debug_level].enum).to eq(described_class::LEVELS)
    end

    it "quiets the program and asks for a plain log by default" do
      expect(params.properties[:nullify_stdio].default).to eq(true)
      expect(params.properties[:plain].default).to eq(true)
    end

    it "defaults the timeout to 120 seconds" do
      expect(params.properties[:timeout].default).to eq(120)
    end
  end

  describe "#call" do
    it "spawns honggfuzz over the program and the input file placeholder" do
      tool.call(command: "tiffinfo")
      expect(tool).to have_received(:exec).with(
        command: "honggfuzz",
        arguments: ["-q", "-v", "--", "tiffinfo", "___FILE___"],
        timeout: 120,
        max_bytes: described_class.max_bytes
      )
    end

    it "puts -- before the program, so a flag of the program is not a flag of honggfuzz" do
      tool.call(command: "tiffinfo", arguments: ["-D", described_class::FILE])
      expect(tool).to have_received(:exec).with(
        hash_including(arguments: ["-q", "-v", "--", "tiffinfo", "-D", "___FILE___"])
      )
    end

    it "passes the corpus as -f" do
      tool.call(command: "tiffinfo", input: "input_dir")
      expect(tool).to have_received(:exec).with(hash_including(arguments: include("-f", "input_dir")))
    end

    it "passes the workspace as -W" do
      tool.call(command: "tiffinfo", workspace: "workspace")
      expect(tool).to have_received(:exec).with(hash_including(arguments: include("-W", "workspace")))
    end

    it "drops the placeholder and passes -s when the input arrives on stdin" do
      tool.call(command: "djpeg", stdin: true)
      expect(tool).to have_received(:exec).with(
        hash_including(arguments: ["-s", "-q", "-v", "--", "djpeg"])
      )
    end

    it "keeps the arguments it is given when the input arrives on stdin" do
      tool.call(command: "djpeg", stdin: true, arguments: ["-outfile", "out.pnm"])
      expect(tool).to have_received(:exec).with(
        hash_including(arguments: ["-s", "-q", "-v", "--", "djpeg", "-outfile", "out.pnm"])
      )
    end

    it "passes the counts as strings" do
      tool.call(
        command: "tiffinfo", threads: 4, iterations: 1000, child_timeout: 5,
        max_file_size: 4096, memory_limit: 512
      )
      expect(tool).to have_received(:exec).with(
        hash_including(arguments: include("-n", "4", "-N", "1000", "-t", "5", "-F", "4096"))
      )
      expect(tool).to have_received(:exec).with(
        hash_including(arguments: include("--rlimit_as", "512"))
      )
    end

    it "passes iterations 0 as -N 0, which is no limit" do
      tool.call(command: "tiffinfo", iterations: 0)
      expect(tool).to have_received(:exec).with(hash_including(arguments: include("-N", "0")))
    end

    it "passes the corpus tuning values as -e, -w, -B, -c and -r" do
      tool.call(
        command: "tiffinfo", extension: "tif", wordlist: "words",
        blacklist: "stackhashes", mutator: "mutate.sh", flip_rate: 0.5
      )
      expect(tool).to have_received(:exec).with(
        hash_including(
          arguments: include(
            "-e", "tif", "-w", "words", "-B", "stackhashes", "-c", "mutate.sh", "-r", "0.5"
          )
        )
      )
    end

    it "passes the report, the log, the debug level and sancov" do
      tool.call(
        command: "tiffinfo", report: "report.txt", logfile: "log.txt",
        debug_level: "4", sancov: true
      )
      expect(tool).to have_received(:exec).with(
        hash_including(arguments: include("-R", "report.txt", "-l", "log.txt", "-C", "-d", "4"))
      )
    end

    it "passes every environment variable as its own -E" do
      tool.call(command: "tiffinfo", environment: ["FOO=1", "BAR=2"])
      expect(tool).to have_received(:exec).with(
        hash_including(arguments: include("-E", "FOO=1", "-E", "BAR=2"))
      )
    end

    it "passes -u and --clear_env" do
      tool.call(command: "tiffinfo", save_all: true, clear_environment: true)
      expect(tool).to have_received(:exec).with(
        hash_including(arguments: include("-u", "--clear_env"))
      )
    end

    it "leaves -q and -v out when they are turned off" do
      tool.call(command: "tiffinfo", nullify_stdio: false, plain: false)
      expect(tool).to have_received(:exec).with(
        hash_including(arguments: ["--", "tiffinfo", "___FILE___"])
      )
    end

    it "passes every flag in a fixed order" do
      tool.call(
        command: "tiffinfo", arguments: ["-D", described_class::FILE], input: "input_dir",
        workspace: "workspace", threads: 4, iterations: 1000, child_timeout: 5,
        max_file_size: 4096, extension: "tif", wordlist: "words", blacklist: "stackhashes",
        mutator: "mutate.sh", flip_rate: 0.5, save_all: true, nullify_stdio: false,
        plain: false, sancov: true, debug_level: "2", report: "report.txt", logfile: "log.txt",
        environment: ["FOO=1"], clear_environment: true, memory_limit: 512
      )
      expect(tool).to have_received(:exec).with(
        hash_including(
          arguments: [
            "-f", "input_dir", "-W", "workspace", "-n", "4", "-N", "1000", "-t", "5",
            "-F", "4096", "-e", "tif", "-w", "words", "-B", "stackhashes", "-c", "mutate.sh",
            "-r", "0.5", "-u", "-C", "-d", "2", "-R", "report.txt", "-l", "log.txt",
            "-E", "FOO=1", "--clear_env", "--rlimit_as", "512",
            "--", "tiffinfo", "-D", "___FILE___"
          ]
        )
      )
    end

    it "forwards the timeout" do
      tool.call(command: "tiffinfo", timeout: 600)
      expect(tool).to have_received(:exec).with(hash_including(timeout: 600))
    end

    it "passes the max bytes" do
      tool.call(command: "tiffinfo", max_bytes: 100)
      expect(tool).to have_received(:exec).with(hash_including(max_bytes: 100))
    end

    it "returns the result as it is when honggfuzz succeeded" do
      expect(tool.call(command: "tiffinfo")).to eq(result)
    end

    it "returns the result as it is when honggfuzz was killed" do
      killed = {ok: false, stdout: "", stderr: "", note: "The command was killed"}
      allow(tool).to receive(:exec).and_return(killed)
      expect(tool.call(command: "tiffinfo", timeout: 5)).to eq(killed)
    end
  end

  describe "validation" do
    it "raises when the command is empty" do
      expect { tool.call(command: "") }
        .to raise_error("command must be the program to fuzz")
    end

    it "raises when the command begins with a dash" do
      expect { tool.call(command: "-x") }
        .to raise_error("command must be a path that doesn't begin with '-'")
    end

    it "raises when an argument of the program is empty" do
      expect { tool.call(command: "tiffinfo", arguments: ["-D", ""]) }
        .to raise_error("an argument of the program can't be empty")
    end

    it "raises when the arguments have no placeholder to mutate" do
      expect { tool.call(command: "tiffinfo", arguments: []) }
        .to raise_error(
          "arguments must include #{described_class::FILE} so the input has somewhere to go, " \
          "or stdin must be true"
        )
    end

    it "raises when the placeholder is given with stdin" do
      expect { tool.call(command: "djpeg", stdin: true, arguments: ["-D", described_class::FILE]) }
        .to raise_error("#{described_class::FILE} must not appear in arguments when stdin is true")
    end

    it "raises when a path is empty" do
      expect { tool.call(command: "tiffinfo", input: "") }
        .to raise_error("input can't be empty")
    end

    it "raises when a path begins with a dash" do
      expect { tool.call(command: "tiffinfo", input: "-f") }
        .to raise_error("input must be a value that doesn't begin with '-'")
    end

    it "raises when threads is not a positive integer" do
      expect { tool.call(command: "tiffinfo", threads: 0) }
        .to raise_error("threads must be a positive integer")
    end

    it "raises when iterations is negative" do
      expect { tool.call(command: "tiffinfo", iterations: -1) }
        .to raise_error("iterations must be zero or a positive integer")
    end

    it "raises when child_timeout is not a positive integer" do
      expect { tool.call(command: "tiffinfo", child_timeout: 0) }
        .to raise_error("child_timeout must be a positive integer")
    end

    it "raises when max_file_size is not a positive integer" do
      expect { tool.call(command: "tiffinfo", max_file_size: 0) }
        .to raise_error("max_file_size must be a positive integer")
    end

    it "raises when memory_limit is not a positive integer" do
      expect { tool.call(command: "tiffinfo", memory_limit: 0) }
        .to raise_error("memory_limit must be a positive integer")
    end

    it "raises when the flip rate is outside 0 through 1" do
      expect { tool.call(command: "tiffinfo", flip_rate: 2) }
        .to raise_error("flip_rate must be between 0 and 1")
    end

    it "raises when the debug level is unknown" do
      expect { tool.call(command: "tiffinfo", debug_level: "5") }
        .to raise_error("debug_level must be one of: 0, 1, 2, 3, 4")
    end

    it "raises when an environment variable is not a NAME=value pair" do
      expect { tool.call(command: "tiffinfo", environment: ["FOO"]) }
        .to raise_error("an environment variable must be a NAME=value pair")
    end
  end
end
