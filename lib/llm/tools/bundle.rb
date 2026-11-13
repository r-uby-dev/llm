# frozen_string_literal: true

class LLM::Tool
  ##
  # The {LLM::Tool::Bundle} class implements
  # a tool that runs a command through `bundle`.
  #
  # It forwards the `BUNDLE_GEMFILE` environment
  # variable when it is set, and when it is not it lets
  # bundle look for a `Gemfile` in the directory the
  # command runs in - which is not necessarily the
  # directory this process runs in.
  class Bundle < self
    require_relative "utils/process"
    include LLM::Tool::Utils::Process

    name "bundle"
    description "Run the 'bundle' command\n" \
                "This command (bundle) is spawned without a shell"
    parameter :arguments, Array[String], "one or more command arguments"
    parameter :timeout, Integer, "the maximum allowed time for the command to run (in seconds)"
    parameter :max_bytes, Integer, "max number of bytes to emit"
    defaults arguments: [], timeout: 60, max_bytes: -> { max_bytes }

    ##
    # @return [LLM::Tool::Bundle]
    def initialize
      @env = ENV["BUNDLE_GEMFILE"] ? {"BUNDLE_GEMFILE" => ENV["BUNDLE_GEMFILE"]} : {}
    end

    ##
    # @param [Array<String>] arguments
    #  One or more command-line arguments
    # @param [Integer] timeout
    #  The maximum allowed time for the command to run (in seconds)
    # @param [Integer] max_bytes
    #  Max number of bytes to emit
    # @return [Hash]
    def call(arguments: [], timeout: 60, max_bytes: self.class.max_bytes)
      execute(command: "bundle", arguments:, env:, timeout:, max_bytes:)
    end

    private

    ##
    # Returns the environment the command runs in: the
    # `BUNDLE_GEMFILE` variable when it is set, and an empty
    # environment when it is not.
    # @return [Hash{String => String}]
    attr_reader :env
  end
end
