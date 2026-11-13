# frozen_string_literal: true

require_relative "../unix"

class LLM::Tool::Unix
  ##
  # The {LLM::Tool::Unix::Cat LLM::Tool::Unix::Cat}
  # class implements a tool that concatenates files and
  # prints them.
  #
  # It spawns `cat` without a shell, and it builds the
  # argument vector itself, so the files and the flags
  # arrive as parameters. `cat` prints more than one file
  # in a single call, where {LLM::Tool::ReadFile} reads
  # one file and returns its lines beside a line number,
  # and the flags shape the output a model reads:
  # `number:` puts a line number at the start of every
  # line, `squeeze_blank:` collapses a run of empty
  # lines, and `show_ends:`, `show_tabs:` and
  # `show_nonprinting:` make trailing whitespace, hard
  # tabs and control characters visible.
  #
  # Every flag is an extension to POSIX that BSD cat and
  # GNU cat share, so the tool works with both. It leaves
  # out `-b`, `-e`, `-t` and `-A` - the other spellings
  # and combinations of the same flags - and `-u` and
  # `-l`, which are about a buffer and a file descriptor
  # that is a pipe here. A path of `-` would read the
  # standard input and block, so it is rejected, and so
  # is a list of no paths.
  #
  # The output of a file can be more than a model can
  # read, so {LLM::Tool::Utils::Process#exec} stops
  # reading at `max_bytes:` and says that it truncated.
  class Cat < self
    name "cat"
    description "Concatenate files and print them\n" \
                "This command (cat) is spawned without a shell"
    parameter :paths, Array[String], "the files to print, in the order given"
    parameter :number, Boolean, "number the output lines, starting at 1"
    parameter :squeeze_blank, Boolean, "squeeze multiple adjacent empty lines into one"
    parameter :show_ends, Boolean, "display a dollar sign at the end of each line"
    parameter :show_tabs, Boolean, "display tab characters as '^I'"
    parameter :show_nonprinting, Boolean, "display non-printing characters so they are visible"
    parameter :timeout, Integer, "the maximum allowed time for the command to run (in seconds)"
    parameter :max_bytes, Integer, "max number of bytes to emit"
    required %i[paths]
    defaults number: false, squeeze_blank: false, show_ends: false,
             show_tabs: false, show_nonprinting: false,
             timeout: 5, max_bytes: -> { max_bytes }

    ##
    # @param [Array<String>] paths
    #  The files to print, in the order given
    # @param [Boolean] number
    #  Number the output lines, starting at 1
    # @param [Boolean] squeeze_blank
    #  Squeeze multiple adjacent empty lines into one
    # @param [Boolean] show_ends
    #  Display a dollar sign at the end of each line
    # @param [Boolean] show_tabs
    #  Display tab characters as '^I'
    # @param [Boolean] show_nonprinting
    #  Display non-printing characters so they are
    #  visible
    # @param [Integer] timeout
    #  The maximum allowed time for cat to run, in
    #  seconds
    # @param [Integer] max_bytes
    #  The max number of bytes to emit
    # @return [Hash]
    def call(paths:, number: false, squeeze_blank: false, show_ends: false,
             show_tabs: false, show_nonprinting: false,
             timeout: 5, max_bytes: self.class.max_bytes)
      validate!(paths:)
      exec(
        command: "cat",
        arguments: arguments(
          paths:, number:, squeeze_blank:, show_ends:, show_tabs:, show_nonprinting:
        ),
        timeout:,
        max_bytes:
      )
    end

    private

    ##
    # Builds the argument vector cat is given: the flags
    # in the order the synopsis of cat(1) lists them,
    # `--` to end the options, then the paths.
    # @return [Array<String>]
    def arguments(paths:, number:, squeeze_blank:, show_ends:, show_tabs:, show_nonprinting:)
      [
        *(show_ends ? ["-E"] : []),
        *(number ? ["-n"] : []),
        *(squeeze_blank ? ["-s"] : []),
        *(show_tabs ? ["-T"] : []),
        *(show_nonprinting ? ["-v"] : []),
        "--",
        *Array(paths)
      ]
    end

    ##
    # @api private
    def validate!(paths:)
      if Array(paths).empty?
        raise RuntimeError, "paths must be one or more files"
      elsif Array(paths).any? { _1.to_s.empty? }
        raise RuntimeError, "a path can't be empty"
      elsif Array(paths).any? { _1.to_s == "-" }
        raise RuntimeError, "a path can't be '-' (that reads standard input)"
      end
    end
  end
end
