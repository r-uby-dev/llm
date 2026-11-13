# frozen_string_literal: true

class LLM::Tool
  ##
  # The {LLM::Tool::Bundle} class implements
  # a tool that runs the `bundle` command.
  #
  # @note
  #  The GEM_HOME and GEM_PATH of the process are
  #  left alone, and a model-provided environment
  #  is mixed into a copy of the process environment
  #  rather than replacing it.
  class Bundle < self
    name "bundle"
    description "Run the bundle command without a shell"
    parameter :args, Array[String], "one or more arguments for bundle"
    parameter :timeout, Integer, "the maximum allowed time for bundle to run (in seconds)"
    parameter :max_bytes, Integer, "max number of bytes to emit"
    parameter :env, Object, "extra environment variables for the command"
    defaults args: [], timeout: 60, max_bytes: :max_bytes, env: nil

    ##
    # @param [Array<String>] args
    #  One or more arguments for bundle
    # @param [Integer] timeout
    #  The maximum time to allow bundle to run, in seconds
    # @param [Integer] max_bytes
    #  The maximum number of bytes to emit
    # @param [Hash, nil] env
    #  Extra environment variables for the command
    # @return [Hash]
    def call(args: [], timeout: 60, max_bytes: self.class.max_bytes, env: nil)
      exec(
        command: "bundle",
        arguments: [*parse!(args:)],
        env: process_env(env),
        timeout:,
        max_bytes:
      )
    end

    private

    ##
    # @api private
    def parse!(args:)
      args
    end

    ##
    # The process environment, mixed into a copy of the
    # model-provided environment rather than replaced by it.
    # @api private
    def process_env(env)
      env.nil? ? {} : ENV.to_h.merge(env.to_h)
    end
  end
end
