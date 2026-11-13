# frozen_string_literal: true

class LLM::Tool::Git
  ##
  # The {LLM::Tool::Git::Log} class implements
  # a tool that lists commits.
  class Log < self
    name "git-log"
    description "List commits"
    parameter :rev, String, "a revision, defaults to HEAD"
    parameter :path, String, "only commits that touch this path"
    parameter :max_count, Integer, "how many commits to return"
    parameter :timeout, Integer, "the maximum allowed time for git to run (in seconds)"
    defaults rev: "HEAD", path: nil, max_count: 10, timeout: DEFAULT_TIMEOUT

    ##
    # @param [String] rev
    #  A revision
    # @param [String, nil] path
    #  An optional path
    # @param [Integer] max_count
    #  The maximum number of commits to return
    # @param [Integer] timeout
    #  The maximum time to allow git to run, in seconds
    # @param [String, nil] cwd
    #  The directory git runs in
    # @return [Hash]
    def call(rev: "HEAD", path: nil, max_count: 10, timeout: DEFAULT_TIMEOUT, cwd: nil)
      execute(
        command: "git",
        arguments: [*chdir(cwd), *parse!(rev:, path:, max_count:)],
        env:,
        timeout:
      )
    end

    private

    ##
    # @api private
    def parse!(rev:, path:, max_count:)
      arguments = ["log", "--oneline", "--max-count=#{max_count}", rev]
      arguments += ["--", path] if path
      arguments
    end
  end
end
