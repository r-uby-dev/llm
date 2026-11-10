# frozen_string_literal: true

require "setup"
require "tmpdir"
require "llm/tools/git"

RSpec.describe LLM::Tool::Git::LsFiles do
  let(:tool) { described_class.new }
  let(:dir) { Dir.mktmpdir("git-ls-files-spec") }

  before do
    skip "git is not on the PATH" unless command_available?("git")
    Dir.chdir(dir) { make_repo! }
  end

  around do |example|
    Dir.chdir(dir) { example.call }
    FileUtils.rm_rf(dir)
  end

  describe ".function" do
    it "defines the path parameter" do
      expect(described_class.function.params.properties.keys).to contain_exactly("path", "timeout", "cwd")
    end
  end

  describe "#call" do
    it "lists the tracked files" do
      expect(tool.call[:stdout]).to eq("file.txt\n")
    end

    it "does not list an untracked file" do
      File.write("new.txt", "hi\n")
      expect(tool.call[:stdout]).to eq("file.txt\n")
    end

    it "lists only the given path" do
      FileUtils.mkdir_p("lib")
      File.write("lib/a.rb", "a\n")
      git!("add", "lib/a.rb")
      git!("commit", "-m", "add lib/a.rb")
      expect(tool.call(path: "lib")[:stdout]).to eq("lib/a.rb\n")
    end
  end
end
