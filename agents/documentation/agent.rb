#!/usr/bin/env ruby
# frozen_string_literal: true

require "llm"
require "llm/tools"
require "fileutils"
require_relative "subagent"

class Agent < LLM::Agent
  set name:        :set_name,
      description: :set_description,
      tools:       :set_tools,
      path:        :set_path,
      tracer:      :set_tracer

  def changelog
    talk([
      "edit the changelog",
      "verify the subagent's work",
      "recall the subagent again if neccessary"
    ])
  end

  include Module.new {
    private

    def set_name
      "docs"
    end

    def set_description
      "works with docs"
    end

    def set_tools
      [LLM::Tool::ReadFile, SubAgent]
    end

    def set_path
      File.join(__dir__, "memory.json")
    end

    def set_tracer
      LLM::Tracer.multi llm, LLM::Tracer::PrettyLogger
    end
  }
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
