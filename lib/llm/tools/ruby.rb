# frozen_string_literal: true

class LLM::Tool
  ##
  # The {LLM::Tool::Ruby LLM::Tool::Ruby} tool
  # evaluates a string of Ruby code by spawning
  # a Ruby process with `-e` option.
  class Ruby < self
    require "rbconfig"
    require "llm/core_ext/rbconfig"
    require_relative "exec"

    name "ruby"
    description "Runs a string of ruby code\n" \
                "This command (ruby) is spawned without a shell"
    parameter :code, String, "a string of ruby code"
    parameter :timeout, Integer, "maximum runtime before timeout"
    parameter :max_bytes, Integer, "max number of bytes to emit"
    required %i[code]
    defaults timeout: 15, max_bytes: -> { Exec.max_bytes }

    ##
    # @param [String] code
    #  Ruby code
    # @param [Integer] timeout
    #  Runtime timeout
    # @param [Integer] max_bytes
    #  Max bytes to emit
    # @return [Hash]
    def call(code:, timeout: 15, max_bytes: Exec.max_bytes)
      Exec.new.call(
        command: RbConfig.ruby,
        arguments: ["-e", code],
        timeout:,
        max_bytes:
      )
    end
  end
end
