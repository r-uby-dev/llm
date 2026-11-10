# frozen_string_literal: true

class LLM::Tool::Git
  ##
  # The {LLM::Tool::Git::Pull} class implements a tool
  # that pulls the changes of a remote branch into the
  # current branch.
  class Pull < self
    name "git-pull"
    description "Pull changes from a remote into the current branch"
    parameter :remote, String, "the remote to pull from (eg origin)"
    parameter :branch, String, "the branch to pull from (eg main)"
    parameter :timeout, Integer, "the maximum allowed time for git to run (in seconds)"
    defaults remote: nil, branch: nil, timeout: DEFAULT_TIMEOUT

    ##
    # @param [String, nil] remote
    #  An optional remote
    # @param [String, nil] branch
    #  An optional branch, which requires a remote
    # @param [Integer] timeout
    #  The maximum time to allow git to run, in seconds
    # @return [Hash]
    def call(remote: nil, branch: nil, timeout: DEFAULT_TIMEOUT, cwd: Dir.getwd)
      Exec
        .new(env:)
        .call(command: "git", arguments: ["-C", cwd, *parse!(remote:, branch:)], timeout:)
    end

    private

    ##
    # @api private
    def parse!(remote:, branch:)
      raise ArgumentError, "a branch requires a remote" if branch && !remote
      ["pull", *[remote, branch].compact]
    end
  end
end
