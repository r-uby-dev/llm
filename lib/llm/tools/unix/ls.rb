# frozen_string_literal: true

require_relative "../unix"

class LLM::Tool::Unix
  ##
  # The {LLM::Tool::Unix::Ls LLM::Tool::Unix::Ls} class
  # implements a tool that lists directory contents.
  #
  # It spawns `ls` without a shell, and it builds the
  # argument vector itself: the flags, the sort order,
  # `--`, then the paths, so a path that begins with `-`
  # is still a path. With no paths at all `ls` lists the
  # working directory, which is what the tool does when
  # `paths:` is empty.
  #
  # There is no `-1` to ask for: ls(1) prints one entry
  # per line when the output is not a terminal, and the
  # output of a spawned command is never a terminal, so
  # the default is already the shape a model wants. For
  # the same reason there is no colour to ask for -
  # `--color` and `CLICOLOR` only reach a tty unless one
  # of them insists, and an escape sequence would be
  # noise in the result.
  #
  # `sort:` is one flag of three that override each
  # other - `time` (`-t`), `size` (`-S`) and `natural`
  # (`-v`, strverscmp, so `bloem9` sorts before
  # `bloem10`) - plus `none` (`-f`), which turns sorting
  # off and drags `-a` along with it and negates the
  # effect of `-r`. `long:` is the format with the mode,
  # the link count, the owner, the group, the size, the
  # time and the name, and `human:` (`-h`) is the size
  # suffixes that only mean something beside it. The
  # result of {LLM::Tool::Utils::Process#exec} is
  # returned as it is, so the entries are
  # `result[:stdout]`. {LLM::Tool::Ls} answers with
  # `Dir.glob` and spawns nothing; this tool is the
  # command, for the model that asks for it.
  class Ls < self
    ##
    # The sort orders, keyed by the name a model asks
    # for. `name` is how ls sorts when no flag is given.
    # @return [Hash{String => Array<String>}]
    SORTS = {
      "name" => [],
      "time" => ["-t"],
      "size" => ["-S"],
      "natural" => ["-v"],
      "none" => ["-f"]
    }.freeze

    name "ls"
    description "List directory contents\n" \
                "This command (ls) is spawned without a shell"
    parameter :paths, Array[String], "the files and directories to list (default is the working directory)"
    parameter :all, Boolean, "include the entries that begin with a dot (-a)"
    parameter :almost_all, Boolean, "include the dot entries but not . and .. (-A)"
    parameter :long, Boolean, "the long format: mode, links, owner, group, size, time, name (-l)"
    parameter :human, Boolean, "unit suffixes for the sizes of a long listing (-h)"
    parameter :classify, Boolean, "append /, *, @ and | to the entries by type (-F)"
    parameter :inode, Boolean, "print the file serial number of each entry (-i)"
    parameter :recursive, Boolean, "list the subdirectories recursively (-R)"
    parameter :directory, Boolean, "list directories as plain files, not their contents (-d)"
    parameter :sort, Enum[*SORTS.keys], "the sort order"
    parameter :reverse, Boolean, "reverse the order of the sort (-r)"
    parameter :timeout, Integer, "the maximum allowed time for the command to run (in seconds)"
    parameter :max_bytes, Integer, "max number of bytes to emit"
    defaults paths: [], all: false, almost_all: false, long: false, human: false,
             classify: false, inode: false, recursive: false, directory: false,
             sort: "name", reverse: false, timeout: 5, max_bytes: -> { max_bytes }

    ##
    # @param [Array<String>] paths
    #  The files and directories to list. With none, ls
    #  lists the working directory
    # @param [Boolean] all
    #  Include the entries that begin with a dot
    # @param [Boolean] almost_all
    #  Include the dot entries but not `.` and `..`
    # @param [Boolean] long
    #  The long format
    # @param [Boolean] human
    #  Unit suffixes for the sizes of a long listing
    # @param [Boolean] classify
    #  Append a character to each entry that says what it
    #  is
    # @param [Boolean] inode
    #  Print the file serial number of each entry
    # @param [Boolean] recursive
    #  List the subdirectories recursively
    # @param [Boolean] directory
    #  List directories as plain files
    # @param [String] sort
    #  The sort order, one of {SORTS}
    # @param [Boolean] reverse
    #  Reverse the order of the sort
    # @param [Integer] timeout
    #  The maximum allowed time for ls to run, in seconds
    # @param [Integer] max_bytes
    #  The max number of bytes to emit
    # @return [Hash]
    def call(paths: [], all: false, almost_all: false, long: false, human: false,
             classify: false, inode: false, recursive: false, directory: false,
             sort: "name", reverse: false, timeout: 5,
             max_bytes: self.class.max_bytes)
      validate!(paths:, sort:)
      exec(
        command: "ls",
        arguments: arguments(
          paths:, all:, almost_all:, long:, human:, classify:, inode:,
          recursive:, directory:, sort:, reverse:
        ),
        timeout:,
        max_bytes:
      )
    end

    private

    ##
    # Builds the argument vector ls is given: the flags,
    # the sort order, `--`, then the paths.
    # @return [Array<String>]
    def arguments(paths:, all:, almost_all:, long:, human:, classify:, inode:,
                  recursive:, directory:, sort:, reverse:)
      [
        *(almost_all ? ["-A"] : []),
        *(classify ? ["-F"] : []),
        *(recursive ? ["-R"] : []),
        *(all ? ["-a"] : []),
        *(directory ? ["-d"] : []),
        *(human ? ["-h"] : []),
        *(inode ? ["-i"] : []),
        *(long ? ["-l"] : []),
        *SORTS.fetch(sort.to_s),
        *(reverse ? ["-r"] : []),
        *(Array(paths).empty? ? [] : ["--", *paths])
      ]
    end

    ##
    # @api private
    def validate!(paths:, sort:)
      if Array(paths).any? { _1.to_s.empty? }
        raise RuntimeError, "a path can't be empty"
      elsif !SORTS.key?(sort.to_s)
        raise RuntimeError, "sort must be one of: #{SORTS.keys.join(', ')}"
      end
    end
  end
end
