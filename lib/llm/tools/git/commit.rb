# frozen_string_literal: true

class LLM::Tool::Git
  ##
  # The {LLM::Tool::Git::Commit} class implements
  # a tool that records changes to the repository.
  class Commit < self
    name "git-commit"
    description "Record changes to the repository"
    parameter :message, String, "the commit message"
    parameter :paths, Array[String], "one or more paths to commit"
    parameter :all, Boolean, "commit every tracked change"
    required %i[message]
    parameter :timeout, Integer, "the maximum allowed time for git to run (in seconds)"
    defaults paths: [], all: false, timeout: DEFAULT_TIMEOUT

    ##
    # @param [String] message
    #  The commit message
    # @param [Array<String>] paths
    #  One or more paths to commit
    # @param [Boolean] all
    #  Whether to commit every tracked change
    # @raise [LLM::Error]
    #  When all: and paths: are given together
    # @param [Integer] timeout
    #  The maximum time to allow git to run, in seconds
    # @return [Hash]
    def call(message:, paths: [], all: false, timeout: DEFAULT_TIMEOUT, cwd: Dir.getwd)
      Exec
        .new(env:)
        .call(command: "git", arguments: ["-C", cwd, *parse!(message:, paths:, all:)], timeout:)
    end

    private

    ##
    # @api private
    def parse!(message:, paths:, all:)
      if all and paths.any?
        raise LLM::Error, "'all' and 'paths' cannot be combined"
      else
        arguments = ["commit", "-m", message]
        arguments << "--all" if all
        arguments += ["--", *paths] if paths.any?
        arguments
      end
    end
  end
end
