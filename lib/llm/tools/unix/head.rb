# frozen_string_literal: true

class LLM::Tool::Unix
  ##
  # The {LLM::Tool::Unix::Head} class implements a tool
  # that prints the first part of a file.
  class Head < self
    name "head"
    description "Print the first part of a file"
    parameter :path, String, "the path to read"
    parameter :lines, Integer, "how many lines to print"
    parameter :timeout, Integer, "the maximum allowed time for head to run (in seconds)"
    required %i[path]
    defaults lines: 10, timeout: DEFAULT_TIMEOUT

    ##
    # @param [String] path
    #  The path to read
    # @param [Integer] lines
    #  How many lines to print
    # @param [Integer] timeout
    #  The maximum time to allow head to run, in seconds
    # @return [Hash]
    def call(path:, lines: 10, timeout: DEFAULT_TIMEOUT)
      exec(command: "head", arguments: [*parse!(path:, lines:)], timeout:)
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
