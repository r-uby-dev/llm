# frozen_string_literal: true

class LLM::Tool
  ##
  # The {LLM::Tool::Rg} class implements a tool that
  # searches for a pattern. It uses ripgrep when it is
  # installed and falls back to `grep -R` when it is not.
  #
  # `grep` does not search the same files by default. It
  # follows symlinks, and it does not honor ignore files,
  # so the two engines can disagree about which files are
  # searched.
  class Rg < self
    name "rg"
    description "Search for a pattern across files"
    parameter :pattern, String, "the pattern to search for"
    parameter :path, String, "the file or directory to search"
    parameter :glob, String, "only search files that match this glob"
    parameter :ignore_case, Boolean, "ignore case when matching"
    parameter :fixed_strings, Boolean, "treat the pattern as a literal string"
    parameter :timeout, Integer, "the maximum allowed time for the search to run (in seconds)"
    required %i[pattern]
    defaults path: ".", glob: nil, ignore_case: false, fixed_strings: false, timeout: 60

    ##
    # @param [String] pattern
    #  The pattern to search for
    # @param [String] path
    #  The file or directory to search
    # @param [String, nil] glob
    #  An optional glob
    # @param [Boolean] ignore_case
    #  Whether to ignore case
    # @param [Boolean] fixed_strings
    #  Whether the pattern is a literal string
    # @param [Integer] timeout
    #  The maximum time to allow the search to run, in seconds
    # @return [Hash]
    def call(pattern:, path: ".", glob: nil, ignore_case: false, fixed_strings: false, timeout: 60)
      if ripgrep?
        exec(command: "rg", arguments: [*rg_arguments(pattern:, path:, glob:, ignore_case:, fixed_strings:)], timeout:)
      else
        exec(command: "grep", arguments: [*grep_arguments(pattern:, path:, glob:, ignore_case:, fixed_strings:)], timeout:)
      end
    end

    private

    ##
    # @api private
    def ripgrep?
      @ripgrep = system("rg", "--version", out: File::NULL, err: File::NULL) if @ripgrep.nil?
      @ripgrep
    end

    ##
    # @api private
    def rg_arguments(pattern:, path:, glob:, ignore_case:, fixed_strings:)
      arguments = ["--line-number", "--no-heading", "--color=never"]
      arguments << "--ignore-case" if ignore_case
      arguments << "--fixed-strings" if fixed_strings
      arguments << "--glob" << glob if glob
      arguments << "--" << pattern << path
      arguments
    end

    ##
    # @api private
    def grep_arguments(pattern:, path:, glob:, ignore_case:, fixed_strings:)
      arguments = ["-R", "-n", "-H"]
      arguments << "-i" if ignore_case
      arguments << "-F" if fixed_strings
      include = glob ? ["--include", glob] : []
      arguments + include + ["--", pattern, path]
    end
  end
end
