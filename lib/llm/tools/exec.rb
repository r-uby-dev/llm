# frozen_string_literal: true

class LLM::Tool
  ##
  # The {LLM::Tool::Exec} class implements a tool that can
  # spawn a command. That can be dangerous given a low-quality
  # model, or a high-quality model that simply makes a bad
  # decision. The risk can be reduced through a confirmation
  # step such as {LLM::Agent.confirm LLM::Agent.confirm}, or
  # by managing the tool loop manually through
  # {LLM::Context LLM::Context}.
  class Exec < self
    require_relative "utils"
    include Utils

    name "exec"
    description "Run a command without a shell"
    parameter :arguments, Array[String], "a command and its argument(s)"
    parameter :timeout, Integer, "the maximum allowed time for the command to run (in seconds)"
    parameter :max_bytes, Integer, "max number of bytes to emit"
    required %i[arguments]
    defaults timeout: 60, max_bytes: :max_bytes

    ##
    # Returns (or sets) the advisory maximum number of bytes
    # this tool returns to the model.
    # @param [Integer, nil] bytes
    #  When given, sets the maximum
    # @return [Integer]
    def self.max_bytes(bytes = UNDEFINED)
      if bytes.equal?(UNDEFINED)
        @max_bytes || 75_000
      else
        @max_bytes = bytes
      end
    end

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
    # @param [Array<String>] arguments
    #  A command and its arguments. The first element is the command name.
    # @param [Integer] timeout
    #  The maximum allowed time for the command to run (in seconds)
    # @param [Integer] max_bytes
    #  the max number of bytes to emit
    # @return [Hash]
    def call(arguments: [], timeout: 60, max_bytes: self.class.max_bytes)
      startat = now
      name    = arguments[0]
      command = spawn(name:, arguments: arguments[1..], env:, max_bytes:)
      killed = catch(:kill) { [wait(command:, timeout:), nil].last }
      if command.not_found?
        {ok: false, error: "command '#{name}' was not found on this system"}
      else
        {ok: command.success?,
        stdout: truncate(command.stdout, max_bytes:),
        stderr: truncate(command.stderr, max_bytes:),
        duration: "#{(now - startat).round(1)} seconds",
        note: killed ? "The command was killed after "            \
                       "exceeding the #{timeout}s timeout. "      \
                       "stdout and stderr are what it produced "  \
                       "before it was killed and both streams "   \
                       "are probably incomplete." : nil
        }.compact
      end
    rescue LLM::Interrupt
      command.kill! if command&.running?
      raise
    end

    private

    ##
    # @return [Hash]
    attr_reader :env

    ##
    # @return [Float]
    def now
      Process.clock_gettime(Process::CLOCK_MONOTONIC)
    end
  end
end
