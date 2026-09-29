# frozen_string_literal: true

##
# The {LLM::Function LLM::Function} class represents a local
# function that can be called by an LLM. Most users should define
# tools as subclasses of {LLM::Tool} instead — Function is the
# lower-level building block that Tool wraps.
#
# @example Tool subclass (preferred for most users)
#   class ReadFile < LLM::Tool
#     name "read-file"
#     description "Read a file from disk"
#     parameter :path, String, "The filename or path"
#     required %i[path]
#
#     def call(path:)
#       {contents: File.read(path)}
#     end
#   end
#
# @example Inline function (block-form DSL)
#   LLM.function(:run_command) do |fn|
#     fn.name "run-command"
#     fn.description "Runs a shell command"
#     fn.params do |schema|
#       schema.object(command: schema.string.required)
#     end
#     fn.define do |command:|
#       {success: Kernel.system(command)}
#     end
#   end
class LLM::Function
  require_relative "function/registry"
  require_relative "function/tracing"
  require_relative "function/array"
  require_relative "function/group"
  require_relative "function/sequential/group"
  require_relative "function/task"
  require_relative "function/sequential/task"
  require_relative "function/thread/task"
  require_relative "function/fiber/task"
  require_relative "function/async/reactor"
  require_relative "function/async/task"
  require_relative "function/thread/group"
  require_relative "function/fiber/group"
  require_relative "function/async/group"
  require_relative "function/window"
  require_relative "function/fork"
  require_relative "function/fork/group"
  require_relative "function/ractor"
  require_relative "function/ractor/group"
