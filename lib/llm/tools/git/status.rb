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
    parameter :max_bytes, Integer, "max number of bytes to emit"
    defaults path: nil, timeout: DEFAULT_TIMEOUT, max_bytes: -> { max_bytes }

    ##
    # @param [String, nil] path
    #  An optional path
    # @param [Integer] timeout
    #  The maximum time to allow git to run, in seconds
    # @param [Integer] max_bytes
    #  The max number of bytes to emit
    # @param [String, nil] cwd
    #  The directory git runs in
    # @return [Hash]
    def call(path: nil, timeout: DEFAULT_TIMEOUT, cwd: nil, max_bytes: self.class.max_bytes)
      exec(
        command: "git",
        arguments: [*chdir(cwd), *parse!(path:)],
        env:,
        timeout:,
        max_bytes:
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
