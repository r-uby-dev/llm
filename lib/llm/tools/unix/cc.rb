# frozen_string_literal: true

require_relative "../unix"

class LLM::Tool::Unix
  ##
  # The {LLM::Tool::Unix::Cc LLM::Tool::Unix::Cc}
  # class implements a tool that compiles C and C++
  # sources.
  #
  # It spawns `cc` without a shell, and it builds the
  # argument vector itself: the stage flag, `-std=`, `-O`,
  # `-g`, `-Wall`, the `-D` and `-I` flags, `-o`, then the
  # sources, then `-L` and `-l`. The sources come before the
  # libraries because the linker reads them in the order it
  # is given them, so `-lm` has to follow the source that
  # calls it. It is the tool that turns an edit into a
  # binary and a diagnostic into the message that explains
  # it; a build that a Makefile describes is
  # {LLM::Tool::Unix::Make}, and a translation unit or two
  # is this one.
  #
  # `cc` is a driver - clang on macOS, gcc on most Linux
  # systems - and every flag the tool passes is one the two
  # share. `stage:` says what the compiler stops at: `link`
  # runs every stage and writes `a.out` when `output:` is
  # not given, `object` writes a `.o`, `assembly` a `.s`,
  # `preprocess` a `.i`, and `syntax` builds nothing at all,
  # which is the quick check after an edit. The result of
  # {LLM::Tool::Utils::Process#execute} is returned as it
  # is, so a compiler diagnostic reaches the model with the
  # stderr and the exit status that carry it.
  #
  # A source that begins with `-` is rejected, so a source
  # is never read as a flag, and so is an empty list of
  # sources, an empty define and an empty library: `-I`,
  # `-D` and `-l` with nothing after them would eat the
  # argument that follows.
  class Cc < self
    ##
    # The stage flags, keyed by the name of the stage a
    # model asks for. A stage of `link` runs every stage,
    # so it has no flag of its own.
    # @return [Hash{String => Array<String>}]
    STAGES = {
      "link" => [],
      "object" => ["-c"],
      "assembly" => ["-S"],
      "preprocess" => ["-E"],
      "syntax" => ["-fsyntax-only"]
    }.freeze

    ##
    # The optimization levels, as they are spelled after the
    # `-O` of `-O2` and `-Os`.
    # @return [Array<String>]
    OPTIMIZATIONS = %w[0 1 2 3 s fast g].freeze

    ##
    # The environment the compiler reads, as the ENVIRONMENT
    # section of clang(1) and gcc(1) describes it. A spawned
    # command inherits $PATH and nothing else, so the
    # variables that add to the include path, the library
    # path and the temporary directory are forwarded when
    # they are set.
    # @return [Array<String>]
    ENVIRONMENT = %w[
      CPATH C_INCLUDE_PATH CPLUS_INCLUDE_PATH
      OBJC_INCLUDE_PATH OBJCPLUS_INCLUDE_PATH
      LIBRARY_PATH MACOSX_DEPLOYMENT_TARGET SDKROOT
      TMPDIR TEMP TMP
    ].freeze

    name "cc"
    description "Compile C and C++ sources with cc\n" \
                "This command (cc) is spawned without a shell"
    parameter :sources, Array[String], "the source files to compile, in the order given"
    parameter :output, String, "the file to write the output to (a.out when linking)"
    parameter :stage, Enum[*STAGES.keys], "the stage to stop at"
    parameter :standard, String, "the language standard to compile for (eg c17, gnu11, c++20)"
    parameter :optimize, Enum[*OPTIMIZATIONS], "the optimization level"
    parameter :debug, Boolean, "generate debug information (-g)"
    parameter :warnings, Boolean, "report the warnings (-Wall)"
    parameter :defines, Array[String], "macros to define, as NAME or NAME=value (-D)"
    parameter :include_directories, Array[String], "directories to search for headers (-I)"
    parameter :library_directories, Array[String], "directories to search for libraries (-L)"
    parameter :libraries, Array[String], "libraries to link against (-l)"
    parameter :timeout, Integer, "the maximum allowed time for the command to run (in seconds)"
    parameter :max_bytes, Integer, "max number of bytes to emit"
    required %i[sources]
    defaults output: nil, stage: "link", standard: nil, optimize: nil, debug: false,
             warnings: false, defines: [], include_directories: [],
             library_directories: [], libraries: [],
             timeout: 120, max_bytes: -> { max_bytes }

    ##
    # @param [Array<String>] sources
    #  The source files to compile, in the order given
    # @param [String, nil] output
    #  The file to write the output to. When it is not
    #  given, a link writes `a.out` and the other stages
    #  write beside the source
    # @param [String] stage
    #  The stage to stop at, one of {STAGES}
    # @param [String, nil] standard
    #  The language standard to compile for, eg `c17`,
    #  `gnu11` or `c++20`
    # @param [String, nil] optimize
    #  The optimization level, one of {OPTIMIZATIONS}
    # @param [Boolean] debug
    #  Generate debug information
    # @param [Boolean] warnings
    #  Report the warnings
    # @param [Array<String>] defines
    #  One or more macros to define, as `NAME` or
    #  `NAME=value`
    # @param [Array<String>] include_directories
    #  One or more directories to search for headers
    # @param [Array<String>] library_directories
    #  One or more directories to search for libraries
    # @param [Array<String>] libraries
    #  One or more libraries to link against
    # @param [Integer] timeout
    #  The maximum allowed time for cc to run, in seconds
    # @param [Integer] max_bytes
    #  The max number of bytes to emit
    # @return [Hash]
    def call(sources:, output: nil, stage: "link", standard: nil, optimize: nil,
             debug: false, warnings: false, defines: [], include_directories: [],
             library_directories: [], libraries: [], timeout: 120,
             max_bytes: self.class.max_bytes)
      validate!(
        sources:, output:, stage:, standard:, optimize:, defines:,
        include_directories:, library_directories:, libraries:
      )
      execute(
        command: "cc",
        arguments: arguments(
          sources:, output:, stage:, standard:, optimize:, debug:, warnings:,
          defines:, include_directories:, library_directories:, libraries:
        ),
        env:,
        timeout:,
        max_bytes:
      )
    end

    private

    ##
    # The environment the compiler runs in, as the
    # ENVIRONMENT section of cc(1) describes it.
    # @return [Hash]
    def env
      ENVIRONMENT.each_with_object({}) do |key, env|
        value = ENV[key].to_s
        env[key] = value unless value.empty?
      end
    end

    ##
    # Builds the argument vector cc is given: the flags,
    # the output, the sources, then `-L` and `-l`, because
    # the linker reads the libraries in the order it is
    # given them.
    # @return [Array<String>]
    def arguments(sources:, output:, stage:, standard:, optimize:, debug:, warnings:,
                  defines:, include_directories:, library_directories:, libraries:)
      [
        *STAGES.fetch(stage.to_s),
        *(standard ? ["-std=#{standard}"] : []),
        *(optimize ? ["-O#{optimize}"] : []),
        *(debug ? ["-g"] : []),
        *(warnings ? ["-Wall"] : []),
        *prefix("-D", defines),
        *prefix("-I", include_directories),
        *(output ? ["-o", output] : []),
        *Array(sources),
        *prefix("-L", library_directories),
        *prefix("-l", libraries)
      ]
    end

    ##
    # Joins a flag with each of its values, so that `-l`
    # and `m` are the single argument `-lm` that cc expects,
    # and a value is never read as a flag of its own.
    # @param [String] flag
    # @param [Array<String>, nil] values
    # @return [Array<String>]
    def prefix(flag, values)
      Array(values).map { "#{flag}#{_1}" }
    end

    ##
    # @api private
    def validate!(sources:, output:, stage:, standard:, optimize:, defines:,
                  include_directories:, library_directories:, libraries:)
      if Array(sources).empty?
        raise RuntimeError, "sources must be one or more files"
      elsif Array(sources).any? { _1.to_s.empty? }
        raise RuntimeError, "a source can't be empty"
      elsif Array(sources).any? { _1.to_s.start_with?("-") }
        raise RuntimeError, "a source can't begin with '-'"
      elsif output && (output.to_s.empty? || output.to_s.start_with?("-"))
        raise RuntimeError, "output must be a path that doesn't begin with '-'"
      elsif !STAGES.key?(stage.to_s)
        raise RuntimeError, "stage must be one of: #{STAGES.keys.join(', ')}"
      elsif standard && !standard.to_s.match?(%r{\A(?:c|gnu|c\+\+|gnu\+\+)[0-9a-z+]*\z})
        raise RuntimeError, "standard must be a C or C++ standard name (eg c17, gnu11, c++20)"
      elsif optimize && !OPTIMIZATIONS.include?(optimize.to_s)
        raise RuntimeError, "optimize must be one of: #{OPTIMIZATIONS.join(', ')}"
      elsif blank?(defines) || blank?(include_directories) ||
            blank?(library_directories) || blank?(libraries)
        raise RuntimeError, "a define, an include directory, a library directory and " \
                            "a library can't be empty"
      elsif Array(defines).any? { !_1.to_s.match?(%r{\A[A-Za-z_][A-Za-z0-9_]*(=.*)?\z}) }
        raise RuntimeError, "a define must be a NAME or a NAME=value pair"
      end
    end

    ##
    # @api private
    def blank?(values)
      Array(values).any? { _1.to_s.empty? }
    end
  end
end
