# frozen_string_literal: true

class LLM::Tool::Git
  ##
  # The {LLM::Tool::Git::Grep} class implements a tool
  # that searches the files git knows about for a
  # pattern.
  class Grep < self
    name "git-grep"
    description "Search the files git knows about for a pattern"
    parameter :pattern, String, "the pattern to search for"
    parameter :paths, Array[String], "only search the files under these pathspecs"
    parameter :rev, String, "the tree or commit to search (default is the working tree)"
    parameter :ignore_case, Boolean, "ignore case differences (-i)"
    parameter :word, Boolean, "match only at word boundaries (-w)"
    parameter :invert, Boolean, "select the lines that do not match (-v)"
    parameter :extended, Boolean, "use a POSIX extended regular expression (-E)"
    parameter :fixed, Boolean, "use fixed strings, not a regular expression (-F)"
    parameter :line_number, Boolean, "prefix each line with its line number (-n)"
    parameter :files_with_matches, Boolean, "show only the names of the files that match (-l)"
    parameter :count, Boolean, "show the number of matching lines per file (-c)"
    parameter :cached, Boolean, "search the index rather than the working tree (--cached)"
    parameter :untracked, Boolean, "search untracked files as well (--untracked)"
    parameter :timeout, Integer, "the maximum allowed time for git to run (in seconds)"
    required %i[pattern]
    defaults paths: [], rev: nil, ignore_case: false, word: false, invert: false,
             extended: false, fixed: false, line_number: false,
             files_with_matches: false, count: false, cached: false,
             untracked: false, timeout: DEFAULT_TIMEOUT

    ##
    # @param [String] pattern
    #  The pattern to search for
    # @param [Array<String>] paths
    #  One or more pathspecs to limit the search to
    # @param [String, nil] rev
    #  The tree or commit to search
    # @param [Boolean] ignore_case
    #  Ignore case differences
    # @param [Boolean] word
    #  Match only at word boundaries
    # @param [Boolean] invert
    #  Select the lines that do not match
    # @param [Boolean] extended
    #  Use a POSIX extended regular expression
    # @param [Boolean] fixed
    #  Use fixed strings, not a regular expression
    # @param [Boolean] line_number
    #  Prefix each line with its line number
    # @param [Boolean] files_with_matches
    #  Show only the names of the files that match
    # @param [Boolean] count
    #  Show the number of matching lines per file
    # @param [Boolean] cached
    #  Search the index rather than the working tree
    # @param [Boolean] untracked
    #  Search untracked files as well
    # @param [Integer] timeout
    #  The maximum time to allow git to run, in seconds
    # @param [String, nil] cwd
    #  The directory git runs in
    # @return [Hash]
    def call(pattern:, paths: [], rev: nil, ignore_case: false, word: false,
             invert: false, extended: false, fixed: false, line_number: false,
             files_with_matches: false, count: false, cached: false,
             untracked: false, timeout: DEFAULT_TIMEOUT, cwd: nil)
      exec(
        command: "git",
        arguments: [
          *chdir(cwd),
          *parse!(
            pattern:, paths:, rev:, ignore_case:, word:, invert:, extended:,
            fixed:, line_number:, files_with_matches:, count:, cached:,
            untracked:
          )
        ],
        env:,
        timeout:
      )
    end

    private

    ##
    # @api private
    def parse!(pattern:, paths:, rev:, ignore_case:, word:, invert:, extended:,
               fixed:, line_number:, files_with_matches:, count:, cached:,
               untracked:)
      if pattern.to_s.empty?
        raise RuntimeError, "pattern can't be empty"
      elsif extended && fixed
        raise RuntimeError, "extended and fixed can't both be set"
      elsif cached && untracked
        raise RuntimeError, "cached and untracked can't both be set"
      elsif Array(paths).any? { _1.to_s.empty? }
        raise RuntimeError, "a path can't be empty"
      end
      [
        "grep",
        *(ignore_case ? ["-i"] : []),
        *(word ? ["-w"] : []),
        *(invert ? ["-v"] : []),
        *(extended ? ["-E"] : []),
        *(fixed ? ["-F"] : []),
        *(line_number ? ["-n"] : []),
        *(files_with_matches ? ["-l"] : []),
        *(count ? ["-c"] : []),
        *(cached ? ["--cached"] : []),
        *(untracked ? ["--untracked"] : []),
        "-e",
        pattern,
        *[rev].compact,
        *(Array(paths).empty? ? [] : ["--", *paths])
      ]
    end
  end
end
