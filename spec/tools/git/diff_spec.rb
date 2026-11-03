# frozen_string_literal: true

require "setup"
require "tmpdir"
require "llm/tools/git"

RSpec.describe LLM::Tool::Git::Diff do
  let(:tool) { described_class.new }
  let(:dir) { Dir.mktmpdir("git-diff-spec") }

  before do
    skip "git is not on the PATH" unless command_available?("git")
    Dir.chdir(dir) { make_repo! }
  end

  around do |example|
    Dir.chdir(dir) { example.call }
    FileUtils.rm_rf(dir)
  end

  describe ".function" do
    let(:params) { described_class.function.params }

    it "defines the rev, path, staged, stat and context parameters" do
      expect(params.properties.keys).to contain_exactly(
        "rev", "path", "staged", "stat", "context"
      )
    end

    it "defaults staged and stat to false" do
      expect(params.properties[:staged].default).to be(false)
      expect(params.properties[:stat].default).to be(false)
    end
  end

  describe "#call" do
    it "shows the unstaged changes" do
      File.write("file.txt", "goodbye\n")
      res = tool.call
      expect(res[:stdout]).to include("-hello")
      expect(res[:stdout]).to include("+goodbye")
    end

    it "shows the staged changes when staged: is true" do
      File.write("file.txt", "goodbye\n")
      git!("add", "file.txt")
      expect(tool.call[:stdout]).to eq("")
      expect(tool.call(staged: true)[:stdout]).to include("+goodbye")
    end

    it "shows a diffstat when stat: is true" do
      File.write("file.txt", "goodbye\n")
      res = tool.call(stat: true)
      expect(res[:stdout]).to include("1 file changed")
      expect(res[:stdout]).to_not include("+goodbye")
    end

    it "limits the context lines when context: is given" do
      File.write("file.txt", "one\ntwo\nthree\nfour\nfive\n")
      git!("commit", "-am", "expand")
      File.write("file.txt", "one\ntwo\nTHREE\nfour\nfive\n")
      expect(tool.call(context: 0)[:stdout]).to include("@@ -3 +3 @@")
    end

    it "diffs against a revision when rev: is given" do
      File.write("file.txt", "goodbye\n")
      expect(tool.call(rev: "HEAD")[:stdout]).to include("+goodbye")
    end
  end
end
