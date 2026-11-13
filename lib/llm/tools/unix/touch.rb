# frozen_string_literal: true

class LLM::Tool::Unix
  ##
  # The {LLM::Tool::Unix::Touch} class implements
  # a tool that creates an empty file, or updates
  # the timestamps of an existing one.
  class Touch < self
    name "touch"
    description "Create an empty file, or update the timestamps of an existing one"
    parameter :path, String, "the file to touch"
    parameter :timeout, Integer, "the maximum allowed time for touch to run (in seconds)"
    required %i[path]
    defaults timeout: DEFAULT_TIMEOUT

    ##
    # @param [String] path
    #  The file to touch
    # @param [Integer] timeout
    #  The maximum time to allow touch to run, in seconds
    # @return [Hash]
    def call(path:, timeout: DEFAULT_TIMEOUT)
      exec(command: "touch", arguments: [*parse!(path:)], timeout:)
    end

    private

    ##
    # @api private
    def parse!(path:)
      if path.empty?
        raise LLM::Error, "'path' must not be empty"
      else
        ["--", path]
      end
    end
  end
end
