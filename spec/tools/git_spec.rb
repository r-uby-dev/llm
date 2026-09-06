# frozen_string_literal: true

require "setup"
require "llm/tools/git"
require "llm/tools/exec"

RSpec.describe LLM::Tool::Git do
  let(:tool) { described_class.new }
  let(:shell) { instance_double(LLM::Tool::Exec) }
  let(:result) { {ok: true, stdout: "output", stderr: ""} }

  before do
    allow(LLM::Tool::Exec).to receive(:new).and_return(shell)
  end

  describe ".function" do
    let(:params) { described_class.function.params }

    it "defines the subcommand param" do
      expect(params.properties[:subcommand]).to be_a(LLM::Schema::String)
    end

    it "marks the subcommand param as required" do
      expect(params.properties[:subcommand]).to be_required
    end

    it "lists the git subcommands" do
      expect(params.properties[:subcommand].enum).to eq(%w[log diff commit checkout branch show])
    end
  end

  describe "#call" do
    before do
      allow(shell).to receive(:call).and_return(result)
    end

    it "runs git through an exec tool" do
      tool.call(subcommand: "status")
      expect(shell).to have_received(:call).with(name: "git", arguments: ["status"], timeout: 5)
    end

    it "returns the exec result" do
      expect(tool.call(subcommand: "status")).to eq(result)
    end

    it "forwards the arguments" do
      tool.call(subcommand: "log", arguments: ["--oneline"])
      expect(shell).to have_received(:call).with(name: "git", arguments: ["log", "--oneline"], timeout: 5)
    end

    it "forwards the timeout" do
      tool.call(subcommand: "status", timeout: 10)
      expect(shell).to have_received(:call).with(name: "git", arguments: ["status"], timeout: 10)
    end

    it "raises when subcommand is missing" do
      expect { tool.call }.to raise_error(ArgumentError, /missing keyword/)
    end
  end
end
