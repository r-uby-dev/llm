#!/usr/bin/env ruby
# frozen_string_literal: true

require "llm"
require "llm/tools"

class Agent < LLM::Agent
  set :name         => "mruby-llm",
      :description  => "mruby-llm backport engineer",
      :instructions => File.read(File.join(__dir__, "prompt.md")),
      :skills       => %w[research.md code.md].map { File.join(__dir__, _1) },
      :tools        => LLM::Tool.subclasses,
      :path         => File.join(__dir__, "..", "..", "contexts", "mruby-llm.json"),
      :tracer       => proc { LLM::Tracer::PrettyLogger.new(llm, io: $stderr) }

  def research
    talk("Let's start our research")
  end

  def code
    talk("Let's implement our research")
  end
end

def main(argv)
  llm     = LLM.deepseek
  agent   = Agent.new(llm)
  command = argv[0]
  case command
  when "research", "code"
    agent.method(command).call
    agent.console
  when "console"
    agent.console
  else
    warn "agent: expected research, code or console but got #{argv[0]}"
    exit 1
  end
end
main(ARGV)
