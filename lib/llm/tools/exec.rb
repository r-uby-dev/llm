# frozen_string_literal: true

class LLM::Tool
  ##
  # The {LLM::Tool::Exec LLM::Tool::Exec} tool spawns
  # a command without a shell. It can be used both
  # directly and indirectly, and multiple other llm.rb
  # tools are built on top of this one.
  class Exec < self
    require_relative "utils/process"
    include Utils::Process

    name "exec"
    description "Run a command without a shell"
    parameter :command, String, "the command to run"
    parameter :arguments, Array[String], "one or more arguments for the command"
    parameter :timeout, Integer, "the maximum allowed time for the command to run (in seconds)"
    parameter :max_bytes, Integer, "max number of bytes to emit"
    required %i[command]
    defaults timeout: 60, max_bytes: :max_bytes

    ##
    # @param [Hash] env
    #  Extra environment variables to set for the command.
    #  This is configuration for the tool instance, not a
    #  model-provided parameter.
    # @return [LLM::Tool::Exec]
    def initialize(env: {})
      @env = env
    end

    ##
    # @param [String] command
    #  The command to run
    # @param [Array<String>] arguments
    #  One or more arguments for the command
    # @param [Integer] timeout
    #  The maximum allowed time for the command to run (in seconds)
    # @param [Integer] max_bytes
    #  the max number of bytes to emit
    # @return [Hash]
    def call(command:, arguments: [], timeout: 60, max_bytes: self.class.max_bytes)
      exec(command:, arguments:, env:, timeout:, max_bytes:)
    end

    private

    ##
    # @return [Hash]
    attr_reader :env
  end
end
