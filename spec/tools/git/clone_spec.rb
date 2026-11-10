# frozen_string_literal: true

require "setup"
require "tmpdir"
require "llm/tools/git"

RSpec.describe LLM::Tool::Git::Clone do
  let(:tool) { described_class.new }
  let(:dir) { Dir.mktmpdir("git-clone-spec") }
  let(:origin) { File.join(dir, "origin") }
  let(:work) { File.join(dir, "work") }

  before do
    skip "git is not on the PATH" unless command_available?("git")
    FileUtils.mkdir_p(origin)
    Dir.chdir(origin) { make_repo! }
  end

  around do |example|
    FileUtils.mkdir_p(work)
    Dir.chdir(work) { example.call }
    FileUtils.rm_rf(dir)
  end

  describe ".function" do
    let(:params) { described_class.function.params }

    it "defines the repository, directory and timeout parameters" do
      expect(params.properties.keys).to contain_exactly("repository", "directory", "timeout", "cwd")
    end

    it "marks repository as required" do
      expect(params.properties[:repository]).to be_required
    end
  end

  describe "#call" do
    it "clones a repository into a directory named after it" do
      expect(tool.call(repository: origin)[:ok]).to be(true)
      expect(File.read(File.join("origin", "file.txt"))).to eq("hello\n")
    end

    it "clones a repository into the given directory" do
      expect(tool.call(repository: origin, directory: "example")[:ok]).to be(true)
      expect(File.read(File.join("example", "file.txt"))).to eq("hello\n")
    end

    it "raises when repository: is not given" do
      expect { tool.call }.to raise_error(ArgumentError)
    end
  end
end
