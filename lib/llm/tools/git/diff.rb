# frozen_string_literal: true

class LLM::Tool::Git
  ##
  # The {LLM::Tool::Git::Diff} class implements
  # a tool that shows the changes between commits,
  # the index, and the working tree.
  class Diff < self
    name "git-diff"
    description "Show changes between commits, the index, and the working tree"
    parameter :rev, String, "diff against this revision"
    parameter :path, String, "only diff this path"
    parameter :staged, Boolean, "diff the index instead of the working tree"
    parameter :stat, Boolean, "show a diffstat instead of a patch"
    parameter :context, Integer, "how many context lines to show"
    parameter :timeout, Integer, "the maximum allowed time for git to run (in seconds)"
    defaults rev: nil, path: nil, staged: false, stat: false, context: nil, timeout: DEFAULT_TIMEOUT

    ##
    # @param [String, nil] rev
    #  An optional revision to diff against
    # @param [String, nil] path
    #  An optional path
    # @param [Boolean] staged
    #  Whether to diff the index
    # @param [Boolean] stat
    #  Whether to show a diffstat instead of a patch
    # @param [Integer, nil] context
    #  The number of context lines to show
    # @param [Integer] timeout
    #  The maximum time to allow git to run, in seconds
    # @return [Hash]
    def call(rev: nil, path: nil, staged: false, stat: false, context: nil, timeout: DEFAULT_TIMEOUT, cwd: Dir.getwd)
      Exec
        .new(env:)
        .call(command: "git", arguments: ["-C", cwd, *parse!(rev:, path:, staged:, stat:, context:)], timeout:)
    end

    private

    ##
    # @api private
    def parse!(rev:, path:, staged:, stat:, context:)
      arguments = ["diff"]
      arguments << "--staged" if staged
      arguments << "--stat" if stat
      arguments << "--unified=#{context}" if context
      arguments << rev if rev
      arguments += ["--", path] if path
      arguments
    end
  end
end
