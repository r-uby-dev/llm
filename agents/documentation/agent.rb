#!/usr/bin/env ruby
# frozen_string_literal: true

require "llm"
require "llm/tools"
require "fileutils"
require_relative "edit_file"

class Intercept < LLM::Intercept
  def self.called!
    @called = true
  end

  def self.called?
    @called
  end

  def call(function:)
    if  function.name == "edit-file"    and
        function.arguments.instructions and
        not self.class.called?
      self.class.called!
      function.return(
        error: true,
        type: "logic_error",
        message: "the first turn can not include instructions " \
                  "for the edit-file subagent but future turns " \
                  "can"
      )
    end
  end
end

class Agent < LLM::Agent
  set name:        :set_name,
      description: :set_description,
      tools:       :set_tools,
      path:        :set_path,
      tracer:      :set_tracer,
      intercept:   :set_intercept

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
      [LLM::Tool::ReadFile, EditFile]
    end

    def set_path
      File.join(__dir__, "memory.json")
    end

    def set_tracer
      LLM::Tracer.multi(llm, LLM::Tracer::PrettyLogger)
    end

    def set_intercept
      LLM::Intercept.multi(llm, Intercept)
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
