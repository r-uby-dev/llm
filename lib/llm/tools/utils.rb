# frozen_string_literal: true

class LLM::Tool
  ##
  # Shared utilities for tool implementations.
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
    # @param [Test::Command] command
    # @param [Integer] timeout
    # @return [void]
    def wait(command:, timeout:)
      start = now
      while command.running?
        if now - start > timeout
          command.kill!
          raise "command timed out after #{timeout}s"
        end
        sleep 0.01
      end
    end

    ##
    # @return [Numeric]
    def now
      Process.clock_gettime(Process::CLOCK_MONOTONIC)
    end
  end
end
