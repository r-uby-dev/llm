# frozen_string_literal: true

class LLM::Tool::Git
  ##
  # The {LLM::Tool::Git::Authors} class implements a tool
  # that lists the authors of a repository, and how many
  # commits each of them has made.
  class Authors < self
    name "git-authors"
    description "List the authors of a repository, and how many commits each has made"
    parameter :path, String, "only count the commits that touch this path"
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
    #  A hash whose `authors` key holds an array of hashes, and
    #  each of those has a `name`, an `email`, and a `commits`
    #  count, with the most commits first
    def call(path: nil, timeout: DEFAULT_TIMEOUT, cwd: nil)
      res = exec(
        command: "git",
        arguments: [*chdir(cwd), *parse!(path:)],
        env:,
        timeout:
      )
      return res unless res[:ok]
      {authors: authors(res[:stdout])}
    end

    private

    ##
    # @api private
    def parse!(path:)
      arguments = ["log", "--format=%aN%x00%aE"]
      arguments += ["--", path] if path
      arguments
    end

    ##
    # @api private
    # @param [String] stdout
    # @return [Array<Hash>]
    def authors(stdout)
      tally = Hash.new(0)
      stdout.each_line do |line|
        name, email = line.chomp.split("\0", 2)
        tally[[name, email]] += 1
      end
      tally
        .map { |(name, email), commits| {name:, email:, commits:} }
        .sort_by { |author| [-author[:commits], author[:name].to_s] }
    end
  end
end
