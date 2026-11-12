# frozen_string_literal: true

require "setup"
require "rbconfig"

RSpec.describe LLM::Command do
  describe "#stdout" do
    let(:command) { described_class.new(RbConfig.ruby, "-e", "print 'hello from stdout'") }
    let(:chunks) { [] }

    before do
      chunks
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

    it "drains stderr while stdout stays open" do
      expect(command.stderr.bytesize).to eq(131_072)
    end

    it "still captures stdout after the large stderr write" do
      command.stderr
      expect(command.stdout).to eq("finished")
    end
  end

  describe "#stderr" do
    let(:command) { described_class.new(RbConfig.ruby, "-e", "warn 'hello from stderr'") }
    let(:chunks) { [] }

    before do
      chunks
      command.stderr { |chunk| chunks << chunk }
    end

    it "yields stderr chunks to the block" do
      expect(chunks.join.chomp).to eq("hello from stderr")
    end

    it "returns the captured stderr" do
      expect(command.stderr.chomp).to eq("hello from stderr")
    end
  end
end
