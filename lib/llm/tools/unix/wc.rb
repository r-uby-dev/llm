# frozen_string_literal: true

class LLM::Tool::Unix
  ##
  # The {LLM::Tool::Unix::Wc} class implements a tool
  # that counts the lines, words, and bytes of a file.
  class Wc < self
    name "wc"
    description "Count the lines, words, and bytes of a file"
    parameter :path, String, "the path to read"
    parameter :timeout, Integer, "the maximum allowed time for wc to run (in seconds)"
    required %i[path]
    defaults timeout: DEFAULT_TIMEOUT

    ##
    # @param [String] path
    #  The path to read
    # @param [Integer] timeout
    #  The maximum time to allow wc to run, in seconds
    # @return [Hash]
    def call(path:, timeout: DEFAULT_TIMEOUT)
      exec(command: "wc", arguments: [*parse!(path:)], timeout:)
    end

    private

    ##
    # @api private
    def parse!(path:)
      if path.empty?
        raise LLM::Error, "'path' must not be empty"
      else
        ["-lwc", "--", path]
      end
    end
  end
end
