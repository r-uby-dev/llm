# frozen_string_literal: true

require "tmpdir"
require "setup"
require "llm/tools/read-file"

RSpec.describe LLM::Tool::ReadFile do
  let(:tool) { described_class.new }
  let(:dir) { Dir.mktmpdir }
  let(:path) { File.join(dir, "sample.txt") }

  after { FileUtils.remove_entry(dir) }

  let(:content) do
    (1..20).map { |i| "line #{i}\n" }.join
  end

  before { File.write(path, content) }

  describe "#call" do
    context "when reading the entire file" do
      subject(:result) { tool.call(path:) }

      it "returns one row per line" do
        expect(result[:lines]).to eq(
          (1..content.lines.size).map { |i| {lineno: i, content: "line #{i}\n"} }
        )
      end

      it "marks the result ok" do
        expect(result[:ok]).to be(true)
      end
    end

    context "when given a start offset" do
      subject(:result) { tool.call(path:, start: 5) }

      it "reads from the start line to the end" do
        expect(result[:lines]).to eq(
          (5..20).map { |i| {lineno: i, content: "line #{i}\n"} }
        )
      end
    end

    context "when given a start and stop offset" do
      subject(:result) { tool.call(path:, start: 5, stop: 10) }

      it "reads the range between start and stop" do
        expect(result[:lines]).to eq(
          (5..10).map { |i| {lineno: i, content: "line #{i}\n"} }
        )
      end
    end

    context "when start is greater than stop" do
      subject(:result) { tool.call(path:, start: 10, stop: 5) }

      it "swaps them and reads the range" do
        expect(result[:lines]).to eq(
          (5..10).map { |i| {lineno: i, content: "line #{i}\n"} }
        )
      end
    end

    context "when the content exceeds max_bytes" do
      before { File.write(path, (1..6).map { |i| "line #{i}\n" }.join) }

      subject(:result) { tool.call(path:, max_bytes: 20) }

      it "marks ok" do
        expect(result[:ok]).to be(true)
      end

      it "flags the result as truncated" do
        expect(result[:truncated]).to be(true)
      end

      it "keeps the lines that fit" do
        expect(result[:lines]).to eq(
          (1..2).map { |i| {lineno: i, content: "line #{i}\n"} } +
            [{lineno: 3, content: "line 3"}]
        )
      end

      it "excludes the truncation marker from the lines" do
        expect(result[:lines]).not_to include(hash_including(content: /\[truncated:/))
        expect(result[:lines]).not_to include(hash_including(content: "...\n"))
      end
    end

    context "when the content fits within max_bytes" do
      before { File.write(path, "short\n") }

      subject(:result) { tool.call(path:, max_bytes: 20) }

      it "does not flag the result as truncated" do
        expect(result[:truncated]).to be(false)
      end

      it "returns the content as lines" do
        expect(result[:lines]).to eq([{lineno: 1, content: "short\n"}])
      end
    end
  end
end
