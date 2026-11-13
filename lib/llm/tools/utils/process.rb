# frozen_string_literal: true

require_relative "../utils"

module LLM::Tool::Utils
  ##
  # The {LLM::Tool::Utils::Process LLM::Tool::Utils::Process}
  # module runs a command on behalf of a tool.
  #
  # Every builtin tool that spawns a command reaches the
  # process through this module, and through {#run} in
  # particular. A tool that replaces {#run} - to run its
  # command in a jail, in a container, or on the far side of
  # an ssh - replaces it for every command it runs, because
  # {#execute} builds a complete command and hands it to that
  # one method.
  module Process
    include LLM::Tool::Utils

    ##
    # Gives the class that includes this module a `max_bytes`
    # of its own.
    # @param [Class] base
    # @return [void]
    def self.included(base)
      base.extend(ClassMethods)
    end

    ##
    # The class-level methods of a tool that spawns a command.
    module ClassMethods
      ##
      # Returns (or sets) the advisory maximum number of bytes
      # this tool returns to the model.
      # @param [Integer, nil] bytes
      #  When given, sets the maximum
      # @return [Integer]
      def max_bytes(bytes = nil)
        if bytes.nil?
          @max_bytes || 75_000
        else
          @max_bytes = bytes
        end
      end
    end

    ##
    # Runs a command to completion, within a timeout, and
    # returns what it wrote.
    #
    # This is the method a tool calls: it builds a command,
    # spawns it with {#run}, waits for it, and caps what it
    # wrote.
    # @param [String] command
    #  The command to run
    # @param [Array<String>] arguments
    #  One or more arguments
    # @param [Hash] env
    #  Extra environment variables to set for the command
    # @param [Integer] timeout
    #  The max number of seconds to wait for the command
    # @param [Integer] max_bytes
    #  The max number of bytes to keep per stream. It
    #  defaults to the including tool's `max_bytes`
    # @return [Hash]
    def execute(command:, arguments: [], env: {}, timeout: 60, max_bytes: self.class.max_bytes)
      startat = now
      spawned = spawn(command:, arguments:, env:, max_bytes:)
      killed = catch(:kill) { [wait(command: spawned, timeout:), nil].last }
      if spawned.not_found?
        {ok: false, error: "command '#{command}' was not found on this system"}
      else
        {ok: spawned.success?,
         stdout: truncate(spawned.stdout, max_bytes:),
         stderr: truncate(spawned.stderr, max_bytes:),
         duration: "#{(now - startat).round(1)} seconds",
         note: killed ? "The command was killed after "            \
                        "exceeding the #{timeout}s timeout. "      \
                        "stdout and stderr are what it produced "  \
                        "before it was killed and both streams "   \
                        "are probably incomplete." : nil
        }.compact
      end
    rescue LLM::Interrupt
      spawned.kill! if spawned&.running?
      raise
    end

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
    # Builds a command from a command and arguments, without starting
    # it, and without going through a shell. The command's stdout and
    # stderr are each capped at `max_bytes`.
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
    def command(command:, arguments:, env: {}, max_bytes: self.class.max_bytes)
      if Integer(max_bytes, exception: false).nil?
        raise ArgumentError, "max_bytes cannot be nil"
      end
      LLM::Command
        .new(command)
        .env(env)
        .arguments(*[*arguments])
        .limit(stdout: max_bytes, stderr: max_bytes)
    end

    ##
    # Spawns a command from a command and arguments.
    # @param [String] command
    #  The command to run
    # @param [Array<String>] arguments
    #  One or more arguments
    # @param [Hash] env
    #  Extra environment variables to set for the command
    # @param [Integer] max_bytes
    #  The max number of bytes to keep per stream
    # @return [LLM::Command]
    #  The spawned command
    def spawn(command:, arguments:, env: {}, max_bytes: self.class.max_bytes)
      run(command(command:, arguments:, env:, max_bytes:))
    end

    ##
    # Starts a command. This is the one method to replace when the
    # commands should run somewhere else - in a jail, in a container,
    # on the far side of an ssh - and the command it is handed is
    # complete: argv, env, byte limits and the directory it runs in.
    # @param [LLM::Command] command
    # @return [LLM::Command]
    #  The spawned command
    def run(command)
      command.spawn
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
    # `success?` returns nil until the status exists, and a command that
    # was never found is the one case where it never will: there was
    # nothing to reap, and `not_found?` is the answer the caller wants.
    # @param [LLM::Command] command
    # @return [Boolean]
    def status_unavailable?(command)
      command.success?.nil? and !command.not_found?
    end

  end
end
