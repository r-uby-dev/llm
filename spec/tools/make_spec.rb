# frozen_string_literal: true

require "setup"
require "llm/tools/unix"

RSpec.describe LLM::Tool::Unix::Make do
  let(:tool) { described_class.new }
  let(:shell) { instance_double(LLM::Tool::Exec) }
  let(:result) { {ok: true, stdout: "cc -o foo foo.c\n", stderr: ""} }

  before do
    allow(LLM::Tool::Exec).to receive(:new).and_return(shell)
    allow(shell).to receive(:call).and_return(result)
  end

  describe ".function" do
    let(:params) { described_class.function.params }

    it "defines the targets, directory, makefile, assignments and jobs params" do
      expect(params.properties.keys).to contain_exactly(
        "targets", "directory", "makefile", "assignments", "jobs",
        "dry_run", "keep_going", "variable", "timeout", "max_bytes"
      )
    end

    it "defines dry_run and keep_going as booleans" do
      expect(params.properties[:dry_run]).to be_a(LLM::Schema::Boolean)
      expect(params.properties[:keep_going]).to be_a(LLM::Schema::Boolean)
    end

    it "defaults the timeout to 120 seconds" do
      expect(params.properties[:timeout].default).to eq(120)
    end
  end

  describe "#call" do
    it "runs make with no arguments" do
      tool.call
      expect(shell).to have_received(:call).with(
        command: "make",
        arguments: [],
        timeout: 120,
        max_bytes: LLM::Tool::Exec.max_bytes
      )
    end

    it "passes the directory as -C" do
      tool.call(directory: Dir.getwd)
      expect(shell).to have_received(:call)
        .with(hash_including(arguments: ["-C", Dir.getwd]))
    end

    it "passes the makefile as -f" do
      tool.call(makefile: "GNUmakefile")
      expect(shell).to have_received(:call)
        .with(hash_including(arguments: ["-f", "GNUmakefile"]))
    end

    it "passes the jobs as -j" do
      tool.call(jobs: 4)
      expect(shell).to have_received(:call)
        .with(hash_including(arguments: ["-j", "4"]))
    end

    it "passes dry_run as -n" do
      tool.call(dry_run: true)
      expect(shell).to have_received(:call)
        .with(hash_including(arguments: ["-n"]))
    end

    it "passes keep_going as -k" do
      tool.call(keep_going: true)
      expect(shell).to have_received(:call)
        .with(hash_including(arguments: ["-k"]))
    end

    it "passes the variable as -V" do
      tool.call(variable: "CFLAGS")
      expect(shell).to have_received(:call)
        .with(hash_including(arguments: ["-V", "CFLAGS"]))
    end

    it "passes the assignments and the targets last" do
      tool.call(assignments: ["PREFIX=/usr/local"], targets: %w[all install])
      expect(shell).to have_received(:call)
        .with(hash_including(arguments: ["PREFIX=/usr/local", "all", "install"]))
    end

    it "passes every argument in a fixed order" do
      arguments = [
        "-C", Dir.getwd, "-f", "Makefile.inc", "-j", "2", "-n", "-k", "-V", "CC",
        "CFLAGS=-g", "all"
      ]
      tool.call(
        directory: Dir.getwd, makefile: "Makefile.inc", jobs: 2, dry_run: true,
        keep_going: true, variable: "CC", assignments: ["CFLAGS=-g"], targets: ["all"]
      )
      expect(shell).to have_received(:call).with(hash_including(arguments:))
    end

    it "forwards the timeout" do
      tool.call(timeout: 600)
      expect(shell).to have_received(:call).with(hash_including(timeout: 600))
    end

    it "passes the max bytes" do
      tool.call(max_bytes: 100)
      expect(shell).to have_received(:call).with(hash_including(max_bytes: 100))
    end

    it "returns the result as it is when the build succeeded" do
      expect(tool.call).to eq(result)
    end

    it "returns the result as it is when the build failed" do
      allow(shell).to receive(:call)
        .and_return({ok: false, stdout: "", stderr: "make: don't know how to make all. Stop\n"})
      expect(tool.call(targets: ["all"])).to eq(
        {ok: false, stdout: "", stderr: "make: don't know how to make all. Stop\n"}
      )
    end
  end

  describe "validation" do
    it "raises when the directory does not exist" do
      expect { tool.call(directory: "/nope/nope") }
        .to raise_error("directory does not exist: /nope/nope")
    end

    it "raises when the jobs are not a positive integer" do
      expect { tool.call(jobs: 0) }
        .to raise_error("jobs must be a positive integer")
    end

    it "raises when the variable is not a variable name" do
      expect { tool.call(variable: "-j") }
        .to raise_error("variable must be the name of a make variable")
    end

    it "raises when an assignment is not a NAME=value pair" do
      expect { tool.call(assignments: ["CFLAGS"]) }
        .to raise_error("assignments must be NAME=value pairs")
    end

    it "raises when a target begins with a dash" do
      expect { tool.call(targets: ["-j"]) }
        .to raise_error("a target can't begin with '-'")
    end
  end
end
