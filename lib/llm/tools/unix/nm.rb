# frozen_string_literal: true

require_relative "../unix"

class LLM::Tool::Unix
  ##
  # The {LLM::Tool::Unix::Nm LLM::Tool::Unix::Nm}
  # class implements a tool that lists the symbols of an
  # object file, an archive or an executable.
  #
  # It is the tool that reads the failure a link
  # produced: `nm -u libfoo.a` lists the symbols the
  # archive refers to and does not define, which is the
  # list a linker prints one line of, and `nm -g` lists
  # the symbols an object exports, which is the list a
  # caller can use. `undefined:` asks the first question
  # and `external:` with `demangle:` the second.
  #
  # It spawns `nm` - GNU nm, or llvm-nm where that is
  # what the system ships - and every flag it passes is
  # one the two accept: `-u`, `-g`, `-C`, `-D`, `-A`,
  # `-S`, `-n` and `-P`. The paths follow `--`, so a path
  # that begins with `-` is read as a path, and a path of
  # `-` is rejected because nm reads the standard input
  # for it and would block. The result of
  # {LLM::Tool::Utils::Process#exec} is returned as it
  # is.
  class Nm < self
    name "nm"
    description "List the symbols of an object file, an archive or an executable\n" \
                "This command (nm) is spawned without a shell"
    parameter :paths, Array[String], "the object files, archives or executables to read"
    parameter :undefined, Boolean, "list only the symbols that are undefined (-u)"
    parameter :external, Boolean, "list only the symbols that are external (-g)"
    parameter :demangle, Boolean, "demangle the symbol names (-C)"
    parameter :dynamic, Boolean, "read the dynamic symbols instead of the normal ones (-D)"
    parameter :file_name, Boolean, "precede each symbol with the file it came from (-A)"
    parameter :size, Boolean, "show the size of each symbol (-S)"
    parameter :numeric_sort, Boolean, "sort the symbols by address (-n)"
    parameter :portable, Boolean, "use the POSIX output format, one symbol per line (-P)"
    parameter :timeout, Integer, "the maximum allowed time for the command to run (in seconds)"
    parameter :max_bytes, Integer, "max number of bytes to emit"
    required %i[paths]
    defaults undefined: false, external: false, demangle: false, dynamic: false,
             file_name: false, size: false, numeric_sort: false, portable: false,
             timeout: 30, max_bytes: -> { max_bytes }

    ##
    # @param [Array<String>] paths
    #  The object files, archives or executables to read
    # @param [Boolean] undefined
    #  List only the symbols that are undefined
    # @param [Boolean] external
    #  List only the symbols that are external
    # @param [Boolean] demangle
    #  Demangle the symbol names
    # @param [Boolean] dynamic
    #  Read the dynamic symbols instead of the normal
    #  ones
    # @param [Boolean] file_name
    #  Precede each symbol with the file it came from
    # @param [Boolean] size
    #  Show the size of each symbol
    # @param [Boolean] numeric_sort
    #  Sort the symbols by address
    # @param [Boolean] portable
    #  Use the POSIX output format
    # @param [Integer] timeout
    #  The maximum allowed time for nm to run, in seconds
    # @param [Integer] max_bytes
    #  The max number of bytes to emit
    # @return [Hash]
    def call(paths:, undefined: false, external: false, demangle: false, dynamic: false,
             file_name: false, size: false, numeric_sort: false, portable: false,
             timeout: 30, max_bytes: self.class.max_bytes)
      validate!(paths:)
      exec(
        command: "nm",
        arguments: arguments(
          paths:, undefined:, external:, demangle:, dynamic:, file_name:,
          size:, numeric_sort:, portable:
        ),
        timeout:,
        max_bytes:
      )
    end

    private

    ##
    # Builds the argument vector nm is given: the flags,
    # then `--`, then the paths.
    # @return [Array<String>]
    def arguments(paths:, undefined:, external:, demangle:, dynamic:, file_name:,
                  size:, numeric_sort:, portable:)
      [
        *(file_name ? ["-A"] : []),
        *(demangle ? ["-C"] : []),
        *(dynamic ? ["-D"] : []),
        *(external ? ["-g"] : []),
        *(numeric_sort ? ["-n"] : []),
        *(portable ? ["-P"] : []),
        *(size ? ["-S"] : []),
        *(undefined ? ["-u"] : []),
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
        raise RuntimeError, "a path of '-' reads the standard input and is not supported"
      end
    end
  end
end
