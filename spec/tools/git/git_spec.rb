# frozen_string_literal: true

require "setup"
require "llm/tools/git"

RSpec.describe LLM::Tool::Git do
  describe ".abstract?" do
    it "returns true for the base class" do
      expect(described_class).to be_abstract
    end

    it "returns false for a tool below it" do
      expect(LLM::Tool::Git::Log).to_not be_abstract
    end
  end

  describe ".name" do
    it "returns nil for the base class" do
      expect(described_class.name).to be_nil
    end
  end

  describe ".registry" do
    it "does not include the base class" do
      expect(LLM::Tool.registry).to_not include(described_class)
    end
  end

  describe ".subclasses" do
    it "does not include the base class" do
      expect(LLM::Tool.subclasses).to_not include(described_class)
    end

    it "returns the eleven git tools" do
      expect(described_class.subclasses.map(&:name)).to contain_exactly(
        "git-authors", "git-branch", "git-checkout", "git-clone", "git-commit",
        "git-diff", "git-log", "git-ls-files", "git-pull", "git-show",
        "git-status"
      )
    end
  end
  {
    Authors: {},
    Branch: {},
    Checkout: {ref: "main"},
    Clone: {repository: "https://example.com/example.git"},
    Commit: {message: "example"},
    Diff: {},
    Log: {},
    LsFiles: {},
    Pull: {},
    Show: {},
    Status: {}
  }.each do |name, arguments|
    describe name.to_s do
      let(:tool_class) { described_class.const_get(name) }
      let(:tool) { tool_class.new }
      let(:exec_result) { {ok: true, stdout: "", stderr: ""} }

      it "exposes an optional timeout defaulting to five seconds" do
        params = tool_class.function.params
        expect(params.properties[:timeout].default).to eq(5)
      end

      it "does not default the directory to the cwd of this process" do
        expect(tool_class.function.params.properties[:cwd].default).to be_nil
      end

      it "passes the default timeout to #execute" do
        expect(tool).to receive(:execute)
          .with(command: "git", arguments: an_instance_of(Array), env: {}, timeout: 5)
          .and_return(exec_result)
        tool.call(**arguments)
      end

      it "passes an explicit timeout to #execute" do
        expect(tool).to receive(:execute)
          .with(command: "git", arguments: an_instance_of(Array), env: {}, timeout: 19)
          .and_return(exec_result)
        tool.call(**arguments, timeout: 19)
      end

      it "passes no directory when none is given" do
        seen = nil
        allow(tool).to receive(:execute) { |**kwargs| seen = kwargs; exec_result }
        tool.call(**arguments)
        expect(seen[:arguments].first).to_not eq("-C")
      end

      it "passes the directory as -C when one is given" do
        seen = nil
        allow(tool).to receive(:execute) { |**kwargs| seen = kwargs; exec_result }
        tool.call(**arguments, cwd: "/tmp")
        expect(seen[:arguments].first(2)).to eq(["-C", "/tmp"])
      end
    end
  end

end
