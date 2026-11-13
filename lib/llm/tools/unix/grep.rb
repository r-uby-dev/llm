# frozen_string_literal: true

require_relative "../unix"

class LLM::Tool::Unix
  ##
  # The {LLM::Tool::Unix::Grep LLM::Tool::Unix::Grep}
  # class implements a tool that searches files for a
  # pattern.
  #
  # It is the fallback for {LLM::Tool::Rg}, which needs a
  # port: grep is POSIX and every unix-like system ships
  # it in the base system, FreeBSD included. It spawns
  # `grep` without a shell, and it sticks to the options
  # POSIX defines - `-E`, `-F`, `-b`, `-c`, `-i`, `-l`,
  # `-n`, `-q`, `-s`, `-v` and `-x`. The BSD and GNU
  # extensions are deliberately absent: no recursion
  # (`-r`/`-R`), no context (`-A`/`-B`/`-C`), no `-o`, no
  # `-w`, no filename headers (`-h`/`-H`), no
  # `--include`. A recursive search is {LLM::Tool::Unix::Find}
  # and this tool, or one script given to
  # {LLM::Tool::BSD::Sh}.
  #
  # The pattern is passed as the operand of `-e`, so a
  # pattern that begins with `-` is a pattern, and the
  # paths follow `--` for the same reason. An empty
  # pattern matches every line, which is why it is
  # refused instead of quietly selecting a whole file.
  #
  # The exit status is grep's: `0` when a line was
  # selected, `1` when none was, above `1` for an error.
  # So a search that matched nothing comes back as
  # `ok: false` with an empty `stdout`, which is the same
  # shape a matchless {LLM::Tool::Rg} has, and it is not
  # a broken command. The result of
  # {LLM::Tool::Utils::Process#exec} is returned as it
  # is otherwise.
  class Grep < self
    name "grep"
    description "Search files for a pattern (POSIX)\n" \
                "This command (grep) is spawned without a shell"
    parameter :pattern, String, "the pattern to search for (given to -e)"
    parameter :paths, Array[String], "the files to search"
    parameter :extended, Boolean, "interpret the pattern as an extended regular expression (-E)"
    parameter :fixed, Boolean, "interpret the pattern as a fixed string (-F)"
    parameter :ignore_case, Boolean, "match without regard to case (-i)"
    parameter :invert, Boolean, "select the lines that do not match (-v)"
    parameter :line, Boolean, "select whole lines that match (-x)"
    parameter :count, Boolean, "print the number of selected lines, not the lines (-c)"
    parameter :files_with_matches, Boolean, "print only the names of the files that match (-l)"
    parameter :line_number, Boolean, "precede each line with its line number (-n)"
    parameter :byte_offset, Boolean, "precede each line with the byte offset of the match (-b)"
    parameter :quiet, Boolean, "print nothing, only set the exit status (-q)"
    parameter :no_messages, Boolean, "suppress the errors of unreadable files (-s)"
    parameter :timeout, Integer, "the maximum allowed time for the command to run (in seconds)"
    parameter :max_bytes, Integer, "max number of bytes to emit"
    required %i[pattern paths]
    defaults extended: false, fixed: false, ignore_case: false, invert: false,
             line: false, count: false, files_with_matches: false,
             line_number: false, byte_offset: false, quiet: false,
             no_messages: false, timeout: 30, max_bytes: -> { max_bytes }

    ##
    # @param [String] pattern
    #  The pattern to search for
    # @param [Array<String>] paths
    #  The files to search
    # @param [Boolean] extended
    #  Interpret the pattern as an extended regular
    #  expression
    # @param [Boolean] fixed
    #  Interpret the pattern as a fixed string
    # @param [Boolean] ignore_case
    #  Match without regard to case
    # @param [Boolean] invert
    #  Select the lines that do not match
    # @param [Boolean] line
    #  Select whole lines that match
    # @param [Boolean] count
    #  Print the number of selected lines
    # @param [Boolean] files_with_matches
    #  Print only the names of the files that match
    # @param [Boolean] line_number
    #  Precede each line with its line number
    # @param [Boolean] byte_offset
    #  Precede each line with the byte offset
    # @param [Boolean] quiet
    #  Print nothing, only set the exit status
    # @param [Boolean] no_messages
    #  Suppress the errors of unreadable files
    # @param [Integer] timeout
    #  The maximum allowed time for grep to run, in
    #  seconds
    # @param [Integer] max_bytes
    #  The max number of bytes to emit
    # @return [Hash]
    def call(pattern:, paths:, extended: false, fixed: false, ignore_case: false,
             invert: false, line: false, count: false, files_with_matches: false,
             line_number: false, byte_offset: false, quiet: false,
             no_messages: false, timeout: 30, max_bytes: self.class.max_bytes)
      validate!(pattern:, paths:, extended:, fixed:)
      exec(
        command: "grep",
        arguments: arguments(
          pattern:, paths:, extended:, fixed:, ignore_case:, invert:, line:,
          count:, files_with_matches:, line_number:, byte_offset:, quiet:,
          no_messages:
        ),
        timeout:,
        max_bytes:
      )
    end

    private

    ##
    # Builds the argument vector grep is given: the
    # flags, `-e` and the pattern, `--`, then the paths.
    # @return [Array<String>]
    def arguments(pattern:, paths:, extended:, fixed:, ignore_case:, invert:, line:,
                  count:, files_with_matches:, line_number:, byte_offset:,
                  quiet:, no_messages:)
      [
        *(extended ? ["-E"] : []),
        *(fixed ? ["-F"] : []),
        *(byte_offset ? ["-b"] : []),
        *(count ? ["-c"] : []),
        *(ignore_case ? ["-i"] : []),
        *(files_with_matches ? ["-l"] : []),
        *(line_number ? ["-n"] : []),
        *(quiet ? ["-q"] : []),
        *(no_messages ? ["-s"] : []),
        *(invert ? ["-v"] : []),
        *(line ? ["-x"] : []),
        "-e",
        pattern,
        "--",
        *paths
      ]
    end

    ##
    # @api private
    def validate!(pattern:, paths:, extended:, fixed:)
      if pattern.to_s.empty?
        raise RuntimeError, "pattern can't be empty"
      elsif extended && fixed
        raise RuntimeError, "extended and fixed can't both be set"
      elsif Array(paths).empty?
        raise RuntimeError, "at least one path is required"
      elsif Array(paths).any? { _1.to_s.empty? }
        raise RuntimeError, "a path can't be empty"
      end
    end
  end
end
