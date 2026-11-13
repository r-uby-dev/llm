# frozen_string_literal: true

require "setup"
require "tmpdir"
require "llm/tools/git"

RSpec.describe LLM::Tool::Git::Grep do
  let(:tool) { described_class.new }
  let(:dir) { Dir.mktmpdir("git-grep-spec") }

  before do
    skip "git is not on the PATH" unless command_available?("git")
    Dir.chdir(dir) { make_repo! }
  end

  around do |example|
    Dir.chdir(dir) { example.call }
    FileUtils.rm_rf(dir)
  end

  describe ".function" do
    it "defines the parameters" do
      expect(described_class.function.params.properties.keys).to contain_exactly(
        "pattern", "paths", "rev", "ignore_case", "word", "invert", "extended",
        "fixed", "line_number", "files_with_matches", "count", "cached",
        "untracked", "timeout", "cwd"
      )
    end

    it "marks the pattern as required" do
      expect(described_class.function.params.properties[:pattern]).to be_required
    end
  end

  describe "#call" do
    it "finds a line in a tracked file" do
      File.write("greeting.txt", "hello\n")
      git!("add", "greeting.txt")
      git!("commit", "-m", "add greeting.txt")
      expect(tool.call(pattern: "hello")[:stdout]).to eq("greeting.txt:hello\n")
    end

    it "does not search an untracked file" do
      File.write("loose.txt", "hello\n")
      expect(tool.call(pattern: "hello")[:stdout]).to eq("")
    end

    it "searches an untracked file as well when asked" do
      File.write("loose.txt", "hello\n")
      expect(tool.call(pattern: "hello", untracked: true)[:stdout])
        .to include("loose.txt:hello")
    end

    it "searches the index rather than the working tree with cached" do
      File.write("greeting.txt", "hello\n")
      git!("add", "greeting.txt")
      git!("commit", "-m", "add greeting.txt")
      File.write("greeting.txt", "goodbye\n")
      expect(tool.call(pattern: "hello", cached: true)[:stdout])
        .to eq("greeting.txt:hello\n")
    end

    it "limits the search to a pathspec" do
      FileUtils.mkdir_p("lib")
      File.write("lib/a.rb", "hello\n")
      File.write("hello.txt", "hello\n")
      git!("add", "lib/a.rb", "hello.txt")
      git!("commit", "-m", "add a.rb and hello.txt")
      expect(tool.call(pattern: "hello", paths: ["lib"])[:stdout])
        .to eq("lib/a.rb:hello\n")
    end

    it "ignores case when asked" do
      File.write("greeting.txt", "Hello\n")
      git!("add", "greeting.txt")
      git!("commit", "-m", "add greeting.txt")
      expect(tool.call(pattern: "hello", ignore_case: true)[:stdout])
        .to eq("greeting.txt:Hello\n")
    end

    it "shows only the file names with files_with_matches" do
      File.write("greeting.txt", "hello\n")
      git!("add", "greeting.txt")
      git!("commit", "-m", "add greeting.txt")
      expect(tool.call(pattern: "hello", files_with_matches: true)[:stdout])
        .to eq("greeting.txt\n")
    end

    it "counts the matching lines with count" do
      File.write("greeting.txt", "hello\nhello\n")
      git!("add", "greeting.txt")
      git!("commit", "-m", "add greeting.txt")
      expect(tool.call(pattern: "hello", count: true)[:stdout])
        .to eq("greeting.txt:2\n")
    end
  end

  describe "validation" do
    it "raises when the pattern is empty" do
      expect { tool.call(pattern: "") }
        .to raise_error("pattern can't be empty")
    end

    it "raises when extended and fixed are both set" do
      expect { tool.call(pattern: "hi", extended: true, fixed: true) }
        .to raise_error("extended and fixed can't both be set")
    end

    it "raises when cached and untracked are both set" do
      expect { tool.call(pattern: "hi", cached: true, untracked: true) }
        .to raise_error("cached and untracked can't both be set")
    end

    it "raises when a path is empty" do
      expect { tool.call(pattern: "hi", paths: [""]) }
        .to raise_error("a path can't be empty")
    end
  end
end
