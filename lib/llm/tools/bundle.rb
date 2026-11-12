# frozen_string_literal: true

class LLM::Tool
  ##
  # The {LLM::Tool::Bundle} class implements
  # a tool that runs a command through `bundle`.
  # It inherits the `BUNDLE_GEMFILE` environment
  # variable when set, or defaults to a `Gemfile`
  # in the current working directory.
  class Bundle < self
    require_relative "exec"

    name "bundle"
    description "Run the 'bundle' command\n" \
                "This command (bundle) is spawned without a shell"
    parameter :arguments, Array[String], "one or more command arguments"
    parameter :timeout, Integer, "the maximum allowed time for the command to run (in seconds)"
    parameter :max_bytes, Integer, "max number of bytes to emit"
    defaults arguments: [], timeout: 60, max_bytes: -> { Unix::Exec.max_bytes }

    ##
    # @return [LLM::Tool::BundleExec]
    def initialize
      @env = {"BUNDLE_GEMFILE" => ENV["BUNDLE_GEMFILE"] || File.join(Dir.getwd, "Gemfile")}
    end

    ##
    # @param [Array<String>] arguments
    #  One or more command-line arguments
    # @param [Integer] timeout
    #  The maximum allowed time for the command to run (in seconds)
    # @param [Integer] max_bytes
    #  Max number of bytes to emit
    # @return [Hash]
    def call(arguments: [], timeout: 60, max_bytes: Unix::Exec.max_bytes)
      Unix::Exec.new(env:).call(
        command: "bundle",
        arguments:,
        timeout:,
        max_bytes:
      )
    end

    private

    ##
    # Returns the `Gemfile` used by this tool:
    # the `BUNDLE_GEMFILE` environment variable
    #  when set, otherwise a `Gemfile` in the
    # current working directory.
    # @return [Hash{String => String}]
    attr_reader :env
  end
end
