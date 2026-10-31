#!/usr/bin/env ruby
# frozen_string_literal: true

require "llm"
require "llm/tools"
require "fileutils"
require_relative "subagent"

class Agent < LLM::Agent
  set name: "docs",
      description: "works with docs",
      tools: [LLM::Tool::ReadFile, SubAgent],
      path: File.join(__dir__, "..", "..", "contexts", "scribe.json"),
      tracer: proc { LLM::Tracer.pretty(llm, io: $stdout) }

  def changelog
    talk([
      "edit the changelog",
      "verify the subagent's work",
      "recall the subagent again if neccessary"
    ])
  end
end

def main(argv)
  llm   = LLM.deepseek
  agent = Agent.new(llm)
  if argv[0] == "console"
    agent.console
  elsif agent.respond_to?(argv[0])
    agent.method(argv[0]).call(*argv[1..])
    agent.console
  else
    warn "agent: expected audit, improvements, review, or console but got #{argv[0]}"
    exit 1
  end
end
main(ARGV)
