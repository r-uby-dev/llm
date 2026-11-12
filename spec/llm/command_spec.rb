# frozen_string_literal: true

require "setup"
require "rbconfig"

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
end
