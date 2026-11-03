# frozen_string_literal: true

require "setup"
require "tmpdir"
require "llm/tools/git"

RSpec.describe LLM::Tool::Git::Branch do
  let(:tool) { described_class.new }
  let(:dir) { Dir.mktmpdir("git-branch-spec") }

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

    it "defines the action and name parameters" do
      expect(params.properties.keys).to contain_exactly("action", "name")
    end

    it "limits the action to a fixed set of values" do
      expect(params.properties[:action].enum).to eq(%w[list create delete])
    end

    it "defaults the action to list" do
      expect(params.properties[:action].default).to eq("list")
    end
  end

  describe "#call" do
    it "lists the branches" do
      expect(tool.call[:stdout]).to eq("* main\n")
    end

    it "lists the branches that match a name" do
      expect(tool.call(name: "main")[:stdout]).to eq("* main\n")
      expect(tool.call(name: "missing")[:stdout]).to eq("")
    end

    it "creates a branch" do
      expect(tool.call(action: "create", name: "feature")[:ok]).to be(true)
      expect(tool.call[:stdout]).to include("feature")
    end

    it "deletes a branch" do
      tool.call(action: "create", name: "feature")
      expect(tool.call(action: "delete", name: "feature")[:ok]).to be(true)
      expect(tool.call[:stdout]).to_not include("feature")
    end

    it "raises when a name is missing" do
      expect { tool.call(action: "create") }
        .to raise_error(LLM::Error, "'name' is required to create a branch")
      expect { tool.call(action: "delete") }
        .to raise_error(LLM::Error, "'name' is required to delete a branch")
    end

    it "raises when the action is unknown" do
      expect { tool.call(action: "rename", name: "feature") }
        .to raise_error(LLM::Error, "action: must be one of: list, create, delete")
    end
  end
end
