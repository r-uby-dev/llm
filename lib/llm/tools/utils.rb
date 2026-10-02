# frozen_string_literal: true

class LLM::Tool
  ##
  # Tool utils.
  module Utils
    ##
    # Truncates a string so a tool return stays bounded.
    # Appends a marker when truncated so the model knows
    # more content was available. Bounds each individual
    # component (string field) a tool returns: a tool that
    # returns multiple strings (eg stdout and stderr) caps
    # each separately.
    # @param [String] content
    # @param [Integer] max_bytes
    #  The max number of bytes to keep
    # @return [String]
    def truncate(content, max_bytes:)
      body, truncated = truncate!(content, max_bytes:)
      truncated ? "#{body}\n...\n[truncated: more than #{max_bytes} bytes]" : body
    end

    ##
    # Performs the truncation and returns a tuple where the
    # first element is the content, which can be either
    # truncated or left intact. The second element is a
    # boolean that indicates whether truncation took place.
    #
    # The difference between {#truncate truncate} and this
    # method is that {#truncate truncate} appends a marker
    # to the truncated content that indicates truncation
    # took place, while this method leaves the content bare
    # so a caller can structure it itself (eg
    # {LLM::Tool::ReadFile}) without parsing the marker back
    # out.
    # @param [String] content
    # @param [Integer] max_bytes
    #  The max number of bytes to keep
    # @return [[String, Boolean]]
    #  A tuple of the content and whether truncation took place
    def truncate!(content, max_bytes:)
      s = content.to_s
      return [s, false] if s.bytesize <= max_bytes
      [s.byteslice(0, max_bytes), true]
    end

    ##
    # Wait for a command to finish, or abort
    # with an error when it exceeds the
    # specified timeout.
    #
    # **A command is waited on until its status is decided, not only until it
    # has stopped running.** `running?` answers whether the process is there,
    # and `success?` answers `nil` until the command has been reaped - so a
    # loop that trusts `running?` alone can leave before the status exists, and
    # the caller reads `ok: nil` beside an output the read had waited for.
    #
    # A command that was never found has no status to wait for: there was
    # nothing to reap, and `not_found?` is the answer the caller wants.
    # @param [Test::Command] command
    # @param [Integer] timeout
    # @return [void]
    def wait(command:, timeout:)
      start = now
      while command.running? || (command.success?.nil? && !command.not_found?)
        if now - start > timeout
          command.kill!
          raise "command timed out after #{timeout}s"
        end
        sleep 0.01
      end
    end

    ##
    # Spawn a command from a name and arguments,
    # without going through a shell. The command's
    # stdout and stderr are each capped at `max_bytes`.
    # @param [String] name
    #  The command name
    # @param [Array<String>] arguments
    #  One or more arguments
    # @param [Hash] env
    #  Extra environment variables to set for the command
    # @param [Integer] max_bytes
    #  The max number of bytes to keep per stream.
    #  Defaults to the including tool's `self.class.max_bytes`.
    # @raise [ArgumentError]
    #  When `max_bytes` is nil
    # @return [Test::Command]
    def spawn(name:, arguments:, env: {}, max_bytes: self.class.max_bytes)
      if Integer(max_bytes, exception: false).nil?
        raise ArgumentError, "max_bytes cannot be nil"
      end
      Command
        .new(name)
        .env(env)
        .arguments(*[*arguments])
        .limit(stdout: max_bytes, stderr: max_bytes)
        .spawn
    end

    ##
    # @return [Numeric]
    def now
      Process.clock_gettime(Process::CLOCK_MONOTONIC)
    end

    ##
    # requires test-cmd.rb
    LLM.require "test-cmd.rb", "~> 2.7.1"
    Command = Test::Command
  end
end
