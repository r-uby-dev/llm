# frozen_string_literal: true

require "setup"
require "tmpdir"
require "llm/tools/git"

RSpec.describe LLM::Tool::Git::Pull do
  let(:tool) { described_class.new }
  let(:dir) { Dir.mktmpdir("git-pull-spec") }
  let(:origin) { File.join(dir, "origin") }
  let(:clone) { File.join(dir, "clone") }

  before do
    skip "git is not on the PATH" unless command_available?("git")
    FileUtils.mkdir_p(origin)
    Dir.chdir(origin) { make_repo! }
    system("git", "clone", origin, clone, out: File::NULL, err: File::NULL)
  end

  around do |example|
    example.call
    FileUtils.rm_rf(dir)
  end

  describe ".function" do
    let(:params) { described_class.function.params }

    it "defines the remote, branch, timeout and cwd parameters" do
      expect(params.properties.keys).to contain_exactly("remote", "branch", "timeout", "cwd")
    end
  end

  describe "#call" do
    it "pulls the changes of the upstream branch" do
      Dir.chdir(origin) { commit!("second") }
      Dir.chdir(clone) do
        expect(tool.call[:ok]).to be(true)
        expect(File.read("file.txt")).to eq("second\n")
      end
    end

    it "pulls from the given remote and branch" do
      Dir.chdir(origin) { commit!("third") }
      Dir.chdir(clone) do
        expect(tool.call(remote: "origin", branch: "main")[:ok]).to be(true)
        expect(File.read("file.txt")).to eq("third\n")
      end
    end

    it "raises when branch: is given without remote:" do
      expect { tool.call(branch: "main") }.to raise_error(ArgumentError)
    end
  end
end
