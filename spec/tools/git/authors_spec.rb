# frozen_string_literal: true

require "setup"
require "tmpdir"
require "llm/tools/git"

RSpec.describe LLM::Tool::Git::Authors do
  let(:tool) { described_class.new }
  let(:dir) { Dir.mktmpdir("git-authors-spec") }

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

    it "defines the path, timeout and cwd parameters" do
      expect(params.properties.keys).to contain_exactly("path", "timeout", "cwd")
    end
  end

  describe "#call" do
    it "lists the author of the repository" do
      expect(tool.call[:authors]).to eq([
        {name: "Spec", email: "spec@example.com", commits: 1}
      ])
    end

    it "counts the commits of each author" do
      commit!("second")
      git!("config", "user.name", "Bob")
      git!("config", "user.email", "bob@example.com")
      commit!("third")
      expect(tool.call[:authors]).to eq([
        {name: "Spec", email: "spec@example.com", commits: 2},
        {name: "Bob", email: "bob@example.com", commits: 1}
      ])
    end

    it "counts only the commits that touch a path" do
      git!("config", "user.name", "Bob")
      git!("config", "user.email", "bob@example.com")
      commit!("second", "other.txt")
      expect(tool.call(path: "other.txt")[:authors]).to eq([
        {name: "Bob", email: "bob@example.com", commits: 1}
      ])
    end

    it "returns the failure of git when there is no repository" do
      Dir.mktmpdir("git-authors-empty") do |empty|
        expect(tool.call(cwd: empty)[:ok]).to be(false)
      end
    end
  end
end
