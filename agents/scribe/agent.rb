#!/usr/bin/env ruby
# frozen_string_literal: true

require "llm"
require "llm/tools"
require "fileutils"

class Agent < LLM::Agent
  set :name         => "scribe",
      :description  => "a documentation engineer",
      :instructions => File.read(File.join(__dir__, "prompt.md")),
      :skills       => %w[regressions.md coverage.md style.md changelog.md].map { File.join(__dir__, _1) },
      :tools        => LLM::Tool.subclasses,
      :path         => File.join(__dir__, "..", "..", "contexts", "scribe.json"),
      :tracer       => proc { LLM::Tracer::PrettyLogger.new(llm, io: $stderr) }

  def changelog
    talk("Let's update the changelog")
  end

  def yardoc
    talk("Run 'bundle exec yardoc' and fix all warnings")
  end

  def regressions
    rm "regressions.md"
    talk("Audit the documentation for regressions and inaccuracies")
  end

  def coverage
    rm "coverage.md"
    talk("Analyze documentation for gaps and improvement opportunities")
  end

  def style
    rm "style.md"
    talk("Review documentation for style violations and consistency issues")
  end

  private

  def rm(doc)
    target = File.join(research_dir, "scribe", doc)
    File.exist?(target) ? FileUtils.rm(target) : nil
  end

  def research_dir
    File.realpath File.join(__dir__, "..", "..", "research")
  end
end

def main(argv)
  llm   = LLM.alibaba
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
