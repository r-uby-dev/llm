# frozen_string_literal: true

class LLM::Tool::Git
  ##
  # The {LLM::Tool::Git::Status} class implements
  # a tool that shows the status of the working tree.
  class Status < self
    name "git-status"
    description "Show the working tree status"
    parameter :path, String, "only report this path"
    parameter :timeout, Integer, "the maximum allowed time for git to run (in seconds)"
    defaults path: nil, timeout: DEFAULT_TIMEOUT

    ##
    # @param [String, nil] path
    #  An optional path
    # @param [Integer] timeout
    #  The maximum time to allow git to run, in seconds
    # @return [Hash]
    def call(path: nil, timeout: DEFAULT_TIMEOUT)
      Exec
        .new(env:)
        .call(arguments: ["git", *parse!(path:)], timeout:)
    end

    private

    ##
    # @api private
    def parse!(path:)
      arguments = ["status", "--porcelain"]
      arguments += ["--", path] if path
      arguments
    end
  end
end
