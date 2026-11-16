# frozen_string_literal: true

require "setup"
require "llm/tools/unix"

RSpec.describe LLM::Tool::Unix::Valgrind do
  let(:tool) { described_class.new }
  let(:result) { {ok: true, stdout: "", stderr: "==1== ERROR SUMMARY: 0 errors\n"} }

  before do
    allow(tool).to receive(:exec).and_return(result)
  end

  describe ".function" do
    let(:params) { described_class.function.params }

    it "defines every param a valgrind run takes" do
      expect(params.properties.keys).to contain_exactly(
        "program", "arguments", "tool", "leak_check", "show_leak_kinds",
        "track_origins", "num_callers", "error_exitcode", "timeout", "max_bytes"
      )
    end

    it "marks the program param as required" do
      expect(params.properties[:program]).to be_required
    end

    it "constrains the tool and the leak check to their values" do
      expect(params.properties[:tool].enum).to eq(described_class::TOOLS)
      expect(params.properties[:leak_check].enum).to eq(described_class::LEAK_CHECKS)
    end

    it "defines track origins as a boolean" do
      expect(params.properties[:track_origins]).to be_a(LLM::Schema::Boolean)
    end

    it "defaults to memcheck, an error exit code of 1 and a 300 second timeout" do
      expect(params.properties[:tool].default).to eq("memcheck")
      expect(params.properties[:error_exitcode].default).to eq(1)
      expect(params.properties[:timeout].default).to eq(300)
    end

    it "defaults max_bytes to the max_bytes of the tool" do
      expect(params.properties[:max_bytes].default).to eq(described_class.max_bytes)
    end
  end

  describe "#call" do
    it "runs the program under memcheck with no options" do
      tool.call(program: "./a.out")
      expect(tool).to have_received(:exec).with(
        command: "valgrind",
        arguments: ["--tool=memcheck", "--error-exitcode=1", "--", "./a.out"],
        env: an_instance_of(::Hash),
        timeout: 300,
        max_bytes: described_class.max_bytes
      )
    end

    it "passes the program arguments after the program" do
      tool.call(program: "./a.out", arguments: %w[--verbose foo])
      expect(tool).to have_received(:exec)
        .with(hash_including(arguments: ["--tool=memcheck", "--error-exitcode=1",
                                         "--", "./a.out", "--verbose", "foo"]))
    end

    it "passes the tool as --tool=" do
      tool.call(program: "./a.out", tool: "cachegrind")
      expect(tool).to have_received(:exec)
        .with(hash_including(arguments: ["--tool=cachegrind", "--error-exitcode=1",
                                         "--", "./a.out"]))
    end

    it "passes the leak check as --leak-check=" do
      tool.call(program: "./a.out", leak_check: "full")
      expect(tool).to have_received(:exec)
        .with(hash_including(arguments: ["--tool=memcheck", "--leak-check=full",
                                         "--error-exitcode=1", "--", "./a.out"]))
    end

    it "passes the leak kinds as a comma separated list" do
      tool.call(program: "./a.out", show_leak_kinds: %w[definite possible])
      expect(tool).to have_received(:exec)
        .with(hash_including(arguments: ["--tool=memcheck", "--show-leak-kinds=definite,possible",
                                         "--error-exitcode=1", "--", "./a.out"]))
    end

    it "passes track origins as --track-origins=yes" do
      tool.call(program: "./a.out", track_origins: true)
      expect(tool).to have_received(:exec)
        .with(hash_including(arguments: ["--tool=memcheck", "--track-origins=yes",
                                         "--error-exitcode=1", "--", "./a.out"]))
    end

    it "passes the number of callers as --num-callers=" do
      tool.call(program: "./a.out", num_callers: 50)
      expect(tool).to have_received(:exec)
        .with(hash_including(arguments: ["--tool=memcheck", "--num-callers=50",
                                         "--error-exitcode=1", "--", "./a.out"]))
    end

    it "passes the error exit code" do
      tool.call(program: "./a.out", error_exitcode: 2)
      expect(tool).to have_received(:exec)
        .with(hash_including(arguments: ["--tool=memcheck", "--error-exitcode=2",
                                         "--", "./a.out"]))
    end

    it "passes every option in a fixed order" do
      arguments = [
        "--tool=memcheck", "--leak-check=full", "--show-leak-kinds=definite,possible",
        "--track-origins=yes", "--num-callers=50", "--error-exitcode=2",
        "--", "./a.out", "foo"
      ]
      tool.call(program: "./a.out", arguments: ["foo"], leak_check: "full",
                show_leak_kinds: %w[definite possible], track_origins: true,
                num_callers: 50, error_exitcode: 2)
      expect(tool).to have_received(:exec).with(hash_including(arguments:))
    end

    it "forwards the timeout" do
      tool.call(program: "./a.out", timeout: 600)
      expect(tool).to have_received(:exec).with(hash_including(timeout: 600))
    end

    it "passes the max bytes" do
      tool.call(program: "./a.out", max_bytes: 100)
      expect(tool).to have_received(:exec).with(hash_including(max_bytes: 100))
    end

    it "returns the result as it is when the program was clean" do
      expect(tool.call(program: "./a.out")).to eq(result)
    end

    it "returns the result as it is when valgrind found an error" do
      stderr = "==1== Invalid read of size 4\n==1==    at 0x1: main (foo.c:3)\n"
      allow(tool).to receive(:exec).and_return({ok: false, stdout: "", stderr:})
      expect(tool.call(program: "./a.out")).to eq({ok: false, stdout: "", stderr:})
    end
  end

  describe "environment" do
    before do
      described_class::ENVIRONMENT.each do |key|
        allow(ENV).to receive(:[]).with(key).and_return(nil)
      end
    end

    it "passes an empty environment when none of the variables are set" do
      tool.call(program: "./a.out")
      expect(tool).to have_received(:exec).with(hash_including(env: {}))
    end

    it "forwards the variables that valgrind reads" do
      allow(ENV).to receive(:[]).with("VALGRIND_OPTS").and_return("--quiet")
      allow(ENV).to receive(:[]).with("DEBUGINFOD_URLS").and_return("https://debuginfod.example.com")
      tool.call(program: "./a.out")
      expect(tool).to have_received(:exec)
        .with(hash_including(env: {"VALGRIND_OPTS" => "--quiet",
                                   "DEBUGINFOD_URLS" => "https://debuginfod.example.com"}))
    end
  end

  describe "validation" do
    it "raises when there is no program" do
      expect { tool.call(program: "") }
        .to raise_error("program must be an executable")
    end

    it "raises when the program begins with a dash" do
      expect { tool.call(program: "--leak-check=full") }
        .to raise_error("program must be a path that doesn't begin with '-'")
    end

    it "raises when the tool is unknown" do
      expect { tool.call(program: "./a.out", tool: "memcheck2") }
        .to raise_error("tool must be one of: memcheck, cachegrind, callgrind, helgrind, " \
                        "drd, massif, dhat, lackey, none")
    end

    it "raises when a memcheck option is given to another tool" do
      expect { tool.call(program: "./a.out", tool: "massif", leak_check: "full") }
        .to raise_error("leak_check, show_leak_kinds and track_origins are memcheck options")
    end

    it "raises when a leak kind is given to another tool" do
      expect { tool.call(program: "./a.out", tool: "callgrind", show_leak_kinds: %w[definite]) }
        .to raise_error("leak_check, show_leak_kinds and track_origins are memcheck options")
    end

    it "raises when track origins is given to another tool" do
      expect { tool.call(program: "./a.out", tool: "helgrind", track_origins: true) }
        .to raise_error("leak_check, show_leak_kinds and track_origins are memcheck options")
    end

    it "raises when the leak check is unknown" do
      expect { tool.call(program: "./a.out", leak_check: "always") }
        .to raise_error("leak_check must be one of: no, summary, yes, full")
    end

    it "raises when a leak kind is empty" do
      expect { tool.call(program: "./a.out", show_leak_kinds: [""]) }
        .to raise_error("a leak kind can't be empty")
    end

    it "raises when a leak kind is unknown" do
      expect { tool.call(program: "./a.out", show_leak_kinds: %w[definite leaked]) }
        .to raise_error("a leak kind must be one of: definite, indirect, possible, reachable")
    end

    it "raises when the number of callers is out of range" do
      expect { tool.call(program: "./a.out", num_callers: 1) }
        .to raise_error("num_callers must be an integer between 2 and 500")
    end

    it "raises when the error exit code is out of range" do
      expect { tool.call(program: "./a.out", error_exitcode: 256) }
        .to raise_error("error_exitcode must be an integer between 0 and 255")
    end
  end
end
