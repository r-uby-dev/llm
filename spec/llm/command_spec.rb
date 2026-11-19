# frozen_string_literal: true

require "setup"
require "rbconfig"
require "timeout"

RSpec.describe LLM::Command do
  ##
  # Windows has a letter-based format
  # to represent the root of the disk
  # (eg D:\)
  let(:root) { Gem.win_platform? ? File.expand_path("/") : "/" }

  describe "#stdout" do
    let(:command) { described_class.new(RbConfig.ruby, "-e", "print 'hello from stdout'") }
    let(:chunks) { [] }

    before do
      command.stdout { |chunk| chunks << chunk }
    end

    it "yields stdout chunks to the block" do
      expect(chunks.join).to eq("hello from stdout")
    end

    it "returns the captured stdout" do
      expect(command.stdout).to eq("hello from stdout")
    end
  end

  describe "reading both streams at once" do
    let(:command) do
      script = "STDERR.write('e' * 131_072); STDOUT.write('finished')"
      described_class.new(RbConfig.ruby, "-e", script)
    end

    before { command.stderr }

    it "drains stderr while stdout stays open" do
      expect(command.stderr.bytesize).to eq(131_072)
    end

    it "still captures stdout after the large stderr write" do
      expect(command.stdout).to eq("finished")
    end
  end

  describe "#stderr" do
    let(:command) { described_class.new(RbConfig.ruby, "-e", "warn 'hello from stderr'") }
    let(:chunks) { [] }

    before do
      command.stderr { |chunk| chunks << chunk }
    end

    it "yields stderr chunks to the block" do
      expect(chunks.join.chomp).to eq("hello from stderr")
    end

    it "returns the captured stderr" do
      expect(command.stderr.chomp).to eq("hello from stderr")
    end
  end

  describe "#to_argv" do
    let(:command) { described_class.new("jexec", "-u", "root", "jail-1") }

    it "returns the command followed by its arguments" do
      expect(command.to_argv).to eq(["jexec", "-u", "root", "jail-1"])
    end

    context "when arguments are added after construction" do
      let(:command) { described_class.new("jexec").arguments("-u", "root") }

      it "picks them up" do
        expect(command.to_argv).to eq(["jexec", "-u", "root"])
      end
    end
  end

  describe "#arguments" do
    let(:ls) { described_class.new("ls").arguments("-l", "/") }
    let(:command) { described_class.new("jexec").arguments(*ls) }

    it "splices another command into the arguments" do
      expect(command.to_argv).to eq(["jexec", "ls", "-l", "/"])
    end

    context "when the command is given without a splat" do
      let(:command) { described_class.new("jexec").arguments(ls) }

      it "splices it too" do
        expect(command.to_argv).to eq(["jexec", "ls", "-l", "/"])
      end
    end

    context "when the command is carried as an argument" do
      let(:echo) { described_class.new("/bin/echo").arguments("carried") }
      let(:command) do
        described_class.new(RbConfig.ruby, "-e", "print ARGV.join(' ')").arguments(echo)
      end

      it "runs it as an argument" do
        expect(command.stdout).to eq("/bin/echo carried")
      end
    end
  end

  describe "#chain" do
    let(:inner) { described_class.new("ls").arguments("-l", "/") }
    let(:command) { described_class.new("jexec").chain(inner) }

    it "splices the argv of the chained command" do
      expect(command.to_argv).to eq(["jexec", "ls", "-l", "/"])
    end

    context "when the chained command sets env" do
      let(:inner) { described_class.new("env").env("FOO" => "bar") }
      let(:command) { described_class.new(RbConfig.ruby, "-e", "print ENV['FOO']").chain(inner) }

      it "carries the env of the chained command" do
        expect(command.stdout).to eq("bar")
      end
    end

    context "when the chained command sets a working directory" do
      let(:inner) { described_class.new("pwd").chdir(root) }
      let(:command) { described_class.new(RbConfig.ruby, "-e", "print Dir.pwd").chain(inner) }

      it "carries the working directory of the chained command" do
        expect(command.stdout).to eq(root)
      end
    end

    context "when the chained command sets stdin" do
      let(:inner) { described_class.new("cat").stdin("hello") }
      let(:command) { described_class.new(RbConfig.ruby, "-e", "print $stdin.read").chain(inner) }

      it "carries the stdin of the chained command" do
        expect(command.stdout).to eq("hello")
      end
    end
  end

  describe "#chdir" do
    let(:command) { described_class.new(RbConfig.ruby, "-e", "print Dir.pwd").chdir(root) }

    it "runs the command in the directory it is given" do
      expect(command.stdout).to eq(root)
    end
  end

  ##
  # A command is over when its child has been reaped, and
  # not when every pipe it handed out has closed. A child
  # it started keeps the pipe open, and reading that as
  # "still running" is how a command that finished holds
  # a caller forever.
  describe "a child the command left behind" do
    let(:script) do
      "Process.spawn(RbConfig.ruby, '-e', 'sleep 5'); print 'hi'"
    end
    let(:command) { described_class.new(RbConfig.ruby, "-e", script) }

    before { command.spawn }

    it "does not wait for the pipe that child is holding" do
      expect { Timeout.timeout(2) { command.status } }.not_to raise_error
    end

    it "hands back the status of the command itself" do
      expect(Timeout.timeout(2) { command.status }.success?).to be(true)
    end

    it "still returns what the command wrote" do
      expect(Timeout.timeout(2) { command.stdout }).to eq("hi")
    end

    it "does not call itself running" do
      Timeout.timeout(2) { command.status }
      expect(command.running?).to be(false)
    end
  end

  ##
  # The pipe holds 64 KiB and the child that reads it is
  # spawned after this, so an input larger than that was
  # written to nobody and blocked the spawn.
  describe "standard input larger than a pipe" do
    let(:command) do
      described_class.new(RbConfig.ruby, "-e", "print $stdin.read")
                     .stdin("x" * 300_000)
    end

    it "writes all of it" do
      expect(Timeout.timeout(5) { command.stdout.bytesize }).to eq(300_000)
    end
  end

  ##
  # A timeout signals the command, and a command that
  # started something else is not stopped by being
  # stopped: the group it leads has to take the signal,
  # or the child it left runs on with its pipes.
  describe "#graceful_exit" do
    let(:script) { "Process.spawn(RbConfig.ruby, '-e', 'sleep 30'); sleep 30" }
    let(:command) { described_class.new(RbConfig.ruby, "-e", script) }

    before { command.spawn }

    it "stops the programs the command started as well" do
      command.graceful_exit
      expect { Timeout.timeout(5) { command.status } }.not_to raise_error
    end
  end
end
