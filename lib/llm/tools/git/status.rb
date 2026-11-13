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
    # @param [String, nil] cwd
    #  The directory git runs in
    # @return [Hash]
    def call(path: nil, timeout: DEFAULT_TIMEOUT, cwd: nil)
      exec(
        command: "git",
        arguments: [*chdir(cwd), *parse!(path:)],
        env:,
        timeout:
      )
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
