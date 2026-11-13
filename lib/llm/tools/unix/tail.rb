# frozen_string_literal: true

class LLM::Tool::Unix
  ##
  # The {LLM::Tool::Unix::Tail} class implements a tool
  # that prints the last part of a file.
  class Tail < self
    name "tail"
    description "Print the last part of a file"
    parameter :path, String, "the path to read"
    parameter :lines, Integer, "how many lines to print"
    parameter :timeout, Integer, "the maximum allowed time for tail to run (in seconds)"
    required %i[path]
    defaults lines: 10, timeout: DEFAULT_TIMEOUT

    ##
    # @param [String] path
    #  The path to read
    # @param [Integer] lines
    #  How many lines to print
    # @param [Integer] timeout
    #  The maximum time to allow tail to run, in seconds
    # @return [Hash]
    def call(path:, lines: 10, timeout: DEFAULT_TIMEOUT)
      exec(command: "tail", arguments: [*parse!(path:, lines:)], timeout:)
    end

    private

    ##
    # @api private
    def parse!(path:, lines:)
      case
      when path.empty? then raise LLM::Error, "'path' must not be empty"
      when lines < 1 then raise LLM::Error, "'lines' must be greater than 0"
      else ["-n", lines.to_s, "--", path]
      end
    end
  end
end
