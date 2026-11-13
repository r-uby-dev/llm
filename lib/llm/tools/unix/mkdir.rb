# frozen_string_literal: true

class LLM::Tool::Unix
  ##
  # The {LLM::Tool::Unix::Mkdir} class implements
  # a tool that creates a directory.
  class Mkdir < self
    name "mkdir"
    description "Create a directory"
    parameter :path, String, "the directory to create"
    parameter :parents, Boolean, "create missing parents, and do not fail if the directory exists"
    parameter :timeout, Integer, "the maximum allowed time for mkdir to run (in seconds)"
    required %i[path]
    defaults parents: false, timeout: DEFAULT_TIMEOUT

    ##
    # @param [String] path
    #  The directory to create
    # @param [Boolean] parents
    #  Whether to create missing parents
    # @param [Integer] timeout
    #  The maximum time to allow mkdir to run, in seconds
    # @return [Hash]
    def call(path:, parents: false, timeout: DEFAULT_TIMEOUT)
      exec(command: "mkdir", arguments: [*parse!(path:, parents:)], timeout:)
    end

    private

    ##
    # @api private
    def parse!(path:, parents:)
      if path.empty?
        raise LLM::Error, "'path' must not be empty"
      elsif parents
        ["-p", "--", path]
      else
        ["--", path]
      end
    end
  end
end
