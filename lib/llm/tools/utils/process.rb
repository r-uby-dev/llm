# frozen_string_literal: true

module LLM::Tool::Utils
  module Process
    ##
    # This method waits for a command to finish
    # but within timeout. A timeout that expires
    # will throw back to the caller.
    # @note
    #  When the timeout expires this method
    #  will throw `:kill` rather than raise
    #  an exception.
    # @raise [UncaughtThrowError]
    #  When the throw does not have a catch.
    # @throw [:kill, true]
    # @param [LLM::Command] command
    # @param [Integer] timeout
    # @return [void]
    def wait(command:, timeout:)
      start = now
      while command.running? || status_unavailable?(command)
        if now - start > timeout
          command.kill!
          throw(:kill, true)
        end
        sleep 0.01
      end
    end

    ##
    # Spawn a command from a command and arguments,
    # without going through a shell. The command's
    # stdout and stderr are each capped at `max_bytes`.
    # @param [String] command
    #  The command to run
    # @param [Array<String>] arguments
    #  One or more arguments
    # @param [Hash] env
    #  Extra environment variables to set for the command
    # @param [Integer] max_bytes
    #  The max number of bytes to keep per stream.
    #  Defaults to the including tool's `self.class.max_bytes`.
    # @raise [ArgumentError]
    #  When `max_bytes` is nil
    # @return [LLM::Command]
    def spawn(command:, arguments:, env: {}, max_bytes: self.class.max_bytes)
      if Integer(max_bytes, exception: false).nil?
        raise ArgumentError, "max_bytes cannot be nil"
      end
      LLM::Command
        .new(command)
        .env(env)
        .arguments(*[*arguments])
        .limit(stdout: max_bytes, stderr: max_bytes)
        .spawn
    end

    ##
    # @return [Numeric]
    def now
      ::Process.clock_gettime(::Process::CLOCK_MONOTONIC)
    end

    private

    ##
    # Whether a command has not been reaped yet.
    #
    # `success?` answers `nil` until the status exists, and a command that was
    # never found is the one case where it never will: there was nothing to
    # reap, and `not_found?` is the answer the caller wants.
    # @param [LLM::Command] command
    # @return [Boolean]
    def status_unavailable?(command)
      command.success?.nil? and !command.not_found?
    end

  end
end
