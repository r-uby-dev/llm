# frozen_string_literal: true

require "setup"
require "llm/tools/git"
require "llm/tools/unix"
require "llm/tools/bsd"
require "llm/tools/bundle"
require "llm/tools/rg"
require "llm/tools/ruby"

##
# Every builtin tool that spawns a command, and the
# arguments one call of it needs. A tool that spawns a
# command has to reach the process through its own #run,
# or a jail that wraps #run wraps nothing.
tools = {
  LLM::Tool::Git::Authors => {},
  LLM::Tool::Git::Branch => {},
  LLM::Tool::Git::Checkout => {ref: "main"},
  LLM::Tool::Git::Clone => {repository: "https://example.com/example.git"},
  LLM::Tool::Git::Commit => {message: "example"},
  LLM::Tool::Git::Diff => {},
  LLM::Tool::Git::Log => {},
  LLM::Tool::Git::LsFiles => {},
  LLM::Tool::Git::Pull => {},
  LLM::Tool::Git::Show => {},
  LLM::Tool::Git::Status => {},
  LLM::Tool::Unix::Apropos => {keywords: ["printf"]},
  LLM::Tool::Unix::Cat => {paths: ["file.txt"]},
  LLM::Tool::Unix::Cc => {sources: ["foo.c"]},
  LLM::Tool::Unix::Find => {},
  LLM::Tool::Unix::Make => {},
  LLM::Tool::Unix::Man => {name: "printf"},
  LLM::Tool::Unix::Mkdir => {path: "a-directory"},
  LLM::Tool::Unix::Nm => {paths: ["foo.o"]},
  LLM::Tool::BSD::PkgInstall => {packages: ["zsh"]},
  LLM::Tool::BSD::PkgSearch => {pattern: "zsh"},
  LLM::Tool::BSD::ProcStat => {pids: [1]},
  LLM::Tool::BSD::Truss => {command: "ls"},
  LLM::Tool::Bundle => {},
  LLM::Tool::Rg => {patterns: ["foo"]},
  LLM::Tool::Ruby => {code: "1"}
}

RSpec.describe "LLM::Tool#run" do
  let(:spawned) do
    instance_double(
      LLM::Command,
      running?: false,
      success?: true,
      not_found?: false,
      stdout: "",
      stderr: ""
    )
  end
  let(:commands) { [] }

  tools.each do |klass, arguments|
    describe klass.name do
      let(:tool) { klass.new }

      before do
        allow(tool).to receive(:run) do |command|
          commands << command
          spawned
        end
      end

      it "reaches the process through #run" do
        tool.call(**arguments)
        expect(tool).to have_received(:run).with(an_instance_of(LLM::Command)).once
        expect(commands.size).to eq(1)
      end

      it "hands #run a command that is complete" do
        tool.call(**arguments)
        command = commands.first
        expect(command.to_argv.size).to be >= 1
        expect(command.to_argv).to all(be_a(::String))
        expect(command.env).to be_a(::Hash)
      end
    end
  end
end
