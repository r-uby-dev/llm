# frozen_string_literal: true

class LLM::Tool::Git
  ##
  # The {LLM::Tool::Git::LsFiles} class implements
  # a tool that lists the files tracked by git.
  class LsFiles < self
    name "git-ls-files"
    description "List files tracked by git"
    parameter :path, String, "only list files under this path"
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
      arguments = ["ls-files"]
      arguments += ["--", path] if path
      arguments
    end
  end
end
