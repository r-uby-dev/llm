# frozen_string_literal: true

require "setup"
require "llm/tools/dir-tree"

RSpec.describe LLM::Tool::DirTree do
  let(:tool) { described_class.new }
  let(:dir) { Dir.mktmpdir }

  before do
    File.write(File.join(dir, "a.txt"), "")
    FileUtils.mkdir_p(File.join(dir, "nested"))
    File.write(File.join(dir, "nested", "b.txt"), "")
  end

  after { FileUtils.remove_entry(dir) }

  describe "#call" do
    subject(:result) { tool.call(path: dir) }

    it "marks the result ok" do
      expect(result[:ok]).to be(true)
    end

    it "returns the files at the top level" do
      expect(result[:tree]).to include("a.txt")
    end

    it "returns a directory as a nested hash" do
      expect(result[:tree]["nested"]).to eq("b.txt" => nil)
    end

    context "when the path does not exist" do
      it "raises" do
        expect { tool.call(path: File.join(dir, "missing")) }
          .to raise_error(RuntimeError, /does not exist/)
      end
    end
  end
end
