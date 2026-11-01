#!/usr/bin/env ruby
# frozen_string_literal: true

require "llm"
require "llm/tools"
require_relative "subagent"

class Agent < LLM::Agent
  set name:         :set_name,
      description:  :set_description,
      instructions: :set_instructions,
      tools:        :set_tools,
      path:         :set_path,
      tracer:       :set_tracer

  def release(version:)
    talk([
      "release version #{version}",
      "verify the subagent's work",
      "recall the subagent again if necessary"
    ])
  end

  private

  def set_name
    "releaser"
  end
  
  def set_description
    "cuts a new gem"
  end

  def set_instructions
    File.read File.join(__dir__, "prompt.md")
  end

  def set_tools
    [LLM::Tool::Git, LLM::Tool::ReadFile, SubAgent]
  end

  def set_path
    File.join(__dir__, "memory.json")
  end

  def set_tracer
    LLM::Tracer.multi(llm, LLM::Tracer::PrettyLogger)
  end
end

def main(argv)
  llm   = LLM.deepseek
  agent = Agent.new(llm)
  case argv[0]
  when "console"
    agent.console
  when "release"
    agent.release(version: ARGV[1])
    agent.console
  else
    warn "agent: expected release, console but got #{argv[0]}"
    exit 1
  end
end
main(ARGV)
