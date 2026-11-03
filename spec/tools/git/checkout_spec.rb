# frozen_string_literal: true

require "setup"
require "tmpdir"
require "llm/tools/git"

RSpec.describe LLM::Tool::Git::Checkout do
  let(:tool) { described_class.new }
  let(:dir) { Dir.mktmpdir("git-checkout-spec") }

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

    it "defines the ref, create and path parameters" do
      expect(params.properties.keys).to contain_exactly("ref", "create", "path")
    end

    it "marks ref as required" do
      expect(params.properties[:ref]).to be_required
    end
  end

  describe "#call" do
    it "creates a branch when create: is true" do
      expect(tool.call(ref: "feature", create: true)[:ok]).to be(true)
      expect(LLM::Tool::Git::Branch.new.call[:stdout]).to include("* feature")
    end

    it "switches branches" do
      tool.call(ref: "feature", create: true)
      expect(tool.call(ref: "main")[:ok]).to be(true)
      expect(LLM::Tool::Git::Branch.new.call[:stdout]).to include("* main")
    end

    it "restores a path from a revision" do
      File.write("file.txt", "goodbye\n")
      expect(tool.call(ref: "HEAD", path: "file.txt")[:ok]).to be(true)
      expect(File.read("file.txt")).to eq("hello\n")
    end

    it "raises when ref: is not given" do
      expect { tool.call }.to raise_error(ArgumentError)
    end
  end
end
