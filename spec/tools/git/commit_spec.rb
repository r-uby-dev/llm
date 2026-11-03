# frozen_string_literal: true

require "setup"
require "tmpdir"
require "llm/tools/git"

RSpec.describe LLM::Tool::Git::Commit do
  let(:tool) { described_class.new }
  let(:dir) { Dir.mktmpdir("git-commit-spec") }

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

    it "defines the message, paths and all parameters" do
      expect(params.properties.keys).to contain_exactly("message", "paths", "all")
    end

    it "marks message as required" do
      expect(params.properties[:message]).to be_required
    end
  end

  describe "#call" do
    it "commits the staged changes" do
      File.write("file.txt", "goodbye\n")
      git!("add", "file.txt")
      res = tool.call(message: "goodbye")
      expect(res[:ok]).to be(true)
      expect(LLM::Tool::Git::Log.new.call[:stdout]).to include("goodbye")
    end

    it "commits every tracked change when all: is true" do
      File.write("file.txt", "goodbye\n")
      File.write("other.txt", "other\n")
      expect(tool.call(message: "everything", all: true)[:ok]).to be(true)
      expect(LLM::Tool::Git::Status.new.call[:stdout]).to eq("?? other.txt\n")
    end

    it "commits only the given paths" do
      File.write("a.txt", "a\n")
      File.write("b.txt", "b\n")
      git!("add", "a.txt", "b.txt")
      expect(tool.call(message: "add a", paths: ["a.txt"])[:ok]).to be(true)
      status = LLM::Tool::Git::Status.new.call[:stdout]
      expect(status).to include("A  b.txt")
      expect(status).to_not include("a.txt")
    end

    it "raises when all: and paths: are combined" do
      expect { tool.call(message: "nope", all: true, paths: ["file.txt"]) }
        .to raise_error(LLM::Error, "'all' and 'paths' cannot be combined")
    end

    it "raises when message: is not given" do
      expect { tool.call }.to raise_error(ArgumentError)
    end
  end
end
