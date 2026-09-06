# frozen_string_literal: true

require "tmpdir"
require "setup"
require "llm/tools/write_file"

RSpec.describe LLM::Tool::WriteFile do
  let(:tool) { described_class.new }
  let(:dir) { Dir.mktmpdir }
  let(:path) { File.join(dir, "sample.txt") }

  after { FileUtils.remove_entry(dir) }

  describe "#call" do
    context "when the content has no trailing newline" do
      it "writes the content with a final newline" do
        tool.call(path:, content: "hello")
        expect(File.read(path)).to eq("hello\n")
      end
    end

    context "when the content already ends in a newline" do
      it "writes the content unchanged" do
        tool.call(path:, content: "hi\n")
        expect(File.read(path)).to eq("hi\n")
      end
    end

    context "when writing" do
      it "returns ok" do
        expect(tool.call(path:, content: "hello")).to eq(ok: true)
      end
    end
  end
end
