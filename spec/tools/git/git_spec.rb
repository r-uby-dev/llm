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

    it "returns the ten git tools" do
      expect(described_class.subclasses.map(&:name)).to contain_exactly(
        "git-authors", "git-branch", "git-checkout", "git-commit",
        "git-diff", "git-log", "git-ls-files", "git-pull", "git-show",
        "git-status"
      )
    end
  end
  {
    Authors: {},
    Branch: {},
    Checkout: {ref: "main"},
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
      let(:executor) { instance_double(LLM::Tool::Exec) }

      it "exposes an optional timeout defaulting to five seconds" do
        params = tool_class.function.params
        expect(params.properties[:timeout].default).to eq(5)
      end

      it "passes the default timeout to Exec" do
        allow(LLM::Tool::Exec).to receive(:new).with(env: {}).and_return(executor)
        expect(executor).to receive(:call).with(command: "git", arguments: an_instance_of(Array), timeout: 5)
        tool_class.new.call(**arguments)
      end

      it "passes an explicit timeout to Exec" do
        allow(LLM::Tool::Exec).to receive(:new).with(env: {}).and_return(executor)
        expect(executor).to receive(:call).with(command: "git", arguments: an_instance_of(Array), timeout: 19)
        tool_class.new.call(**arguments, timeout: 19)
      end
    end
  end

end
