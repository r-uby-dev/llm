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
    defaults path: nil, timeout: DEFAULT_TIMEOUT

    ##
    # @param [String, nil] path
    #  An optional path
    # @param [Integer] timeout
    #  The maximum time to allow git to run, in seconds
    # @return [Hash]
    def call(path: nil, timeout: DEFAULT_TIMEOUT, cwd: Dir.getwd)
      Exec
        .new(env:)
        .call(command: "git", arguments: ["-C", cwd, *parse!(path:)], timeout:)
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
