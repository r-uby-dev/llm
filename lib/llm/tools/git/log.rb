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
    defaults rev: "HEAD", path: nil, max_count: 25

    ##
    # @param [String] rev
    #  A revision
    # @param [String, nil] path
    #  An optional path
    # @param [Integer] max_count
    #  The maximum number of commits to return
    # @return [Hash]
    def call(rev: "HEAD", path: nil, max_count: 25)
      Exec
        .new(env:)
        .call(arguments: parse!(rev:, path:, max_count:))
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
