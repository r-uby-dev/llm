# frozen_string_literal: true

require_relative "../unix"

class LLM::Tool::Unix
  ##
  # The {LLM::Tool::Unix::Cc LLM::Tool::Unix::Cc} class
  # implements a tool that compiles a C, C++ or
  # Objective-C source file.
  #
  # It is the tool that closes the loop that
  # {LLM::Tool::EditFile} opens: a change a model made to
  # a source file is checked by the compiler that will
  # build it, rather than by the model's reading of it.
  # `syntax_only:` asks cc whether the source is valid at
  # all, and a warning of `-Wall` is the answer that a
  # source compiles and is still wrong.
  #
  # The tool spawns `cc` without a shell, and the source
  # comes after `--`, so a path that begins with `-` is
  # read as a path. `$CFLAGS` is not consulted - the
  # flags are the parameters of the tool and nothing
  # else. The result of
  # {LLM::Tool::Utils::Process#exec} is returned as it
  # is.
  class Cc < self
    name "cc"
    description "Compile a C, C++ or Objective-C source file\n" \
                "This command (cc) is spawned without a shell"
    parameter :path, String, "the source file to compile"
    parameter :syntax_only, Boolean, "check the syntax only, and write no output file (-fsyntax-only)"
    parameter :warnings, Boolean, "enable a set of common warnings (-Wall)"
    parameter :warnings_as_errors, Boolean, "make warnings fatal (-Werror)"
    parameter :include_paths, Array[String], "one or more directories to search for headers (-I)"
    parameter :output, String, "the output file (-o)"
    parameter :language, String, "the language of the source (eg 'c', 'c++', 'objective-c')"
    parameter :standard, String, "the language standard (eg 'c11', 'c++17')"
    parameter :timeout, Integer, "the maximum allowed time for the command to run (in seconds)"
    parameter :max_bytes, Integer, "max number of bytes to emit"
    required %i[path]
    defaults syntax_only: false, warnings: true, warnings_as_errors: false,
             include_paths: [], output: nil, language: nil, standard: nil,
             timeout: 60, max_bytes: -> { max_bytes }

    ##
    # @param [String] path
    #  The source file to compile
    # @param [Boolean] syntax_only
    #  Check the syntax only, and write no output file
    # @param [Boolean] warnings
    #  Enable a set of common warnings
    # @param [Boolean] warnings_as_errors
    #  Make warnings fatal
    # @param [Array<String>] include_paths
    #  One or more directories to search for headers
    # @param [String, nil] output
    #  The output file
    # @param [String, nil] language
    #  The language of the source
    # @param [String, nil] standard
    #  The language standard
    # @param [Integer] timeout
    #  The maximum allowed time for cc to run, in seconds
    # @param [Integer] max_bytes
    #  The max number of bytes to emit
    # @return [Hash]
    def call(path:, syntax_only: false, warnings: true, warnings_as_errors: false,
             include_paths: [], output: nil, language: nil, standard: nil,
             timeout: 60, max_bytes: self.class.max_bytes)
      validate!(path:, output:, language:, standard:)
      exec(
        command: "cc",
        arguments: arguments(
          path:, syntax_only:, warnings:, warnings_as_errors:, include_paths:,
          output:, language:, standard:
        ),
        timeout:,
        max_bytes:
      )
    end

    private

    ##
    # Builds the argument vector cc is given: the flags,
    # then `--`, then the source.
    # @return [Array<String>]
    def arguments(path:, syntax_only:, warnings:, warnings_as_errors:, include_paths:,
                  output:, language:, standard:)
      [
        *(syntax_only ? ["-fsyntax-only"] : []),
        *(warnings ? ["-Wall"] : []),
        *(warnings_as_errors ? ["-Werror"] : []),
        *(language ? ["-x", language] : []),
        *(standard ? ["-std=#{standard}"] : []),
        *[*include_paths].flat_map { ["-I", _1] },
        *(output ? ["-o", output] : []),
        "--",
        path
      ]
    end

    ##
    # @api private
    def validate!(path:, output:, language:, standard:)
      if path.to_s.empty?
        raise RuntimeError, "path must be a source file"
      elsif path.to_s == "-"
        raise RuntimeError, "a path of '-' reads the standard input and is not supported"
      elsif output && output.to_s.empty?
        raise RuntimeError, "output can't be empty"
      elsif language && language.to_s.empty?
        raise RuntimeError, "language can't be empty"
      elsif standard && standard.to_s.empty?
        raise RuntimeError, "standard can't be empty"
      end
    end
  end
end
