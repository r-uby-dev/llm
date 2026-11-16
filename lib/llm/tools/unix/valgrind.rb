# frozen_string_literal: true

require_relative "../unix"

class LLM::Tool::Unix
  ##
  # The {LLM::Tool::Unix::Valgrind LLM::Tool::Unix::Valgrind}
  # class implements a tool that runs a program under valgrind
  # and returns the report valgrind writes.
  #
  # It reads the failure a compiler cannot see.
  # {LLM::Tool::Unix::Cc} builds a binary and
  # {LLM::Tool::Unix::Nm} reads its symbols, but a program that
  # writes past the end of an allocation, reads memory it has
  # already freed, or leaks it, only says so under a tool like
  # this one.
  #
  # The tool spawns `valgrind` without a shell and it builds the
  # argument vector itself: `--tool=`, the memcheck options,
  # `--error-exitcode=`, `--`, the program, then the arguments of
  # the program. The `--` is what keeps an argument that begins
  # with `-` an argument of the program, and what keeps a program
  # from being read as an option of valgrind.
  #
  # Valgrind writes its report to stderr and it runs a program
  # tens of times slower, so the timeout defaults to 300 seconds.
  # The `error_exitcode:` defaults to 1 rather than to nil because
  # valgrind otherwise exits with the exit status of the program
  # and a report would arrive as `ok: true`.
  #
  # @see LLM::Tool::Unix::Cc
  # @see LLM::Tool::Unix::Nm
  class Valgrind < self
    ##
    # The tools valgrind ships. `memcheck` is the default: it is
    # the one that reports an invalid read, an invalid write, an
    # uninitialised value and a leak.
    # @return [Array<String>]
    TOOLS = %w[
      memcheck cachegrind callgrind helgrind drd
      massif dhat lackey none
    ].freeze

    ##
    # What memcheck does with a leak when the program exits, from
    # `no` (never check) to `full` (every leak, with a stack
    # trace).
    # @return [Array<String>]
    LEAK_CHECKS = %w[no summary yes full].freeze

    ##
    # The kinds of leak memcheck can report. A `definite` leak is
    # a block nothing points at, an `indirect` leak is a block
    # that only a definite leak points at, and a `possible` leak
    # is a block that something inside it points at.
    # @return [Array<String>]
    LEAK_KINDS = %w[definite indirect possible reachable].freeze

    ##
    # The variables an already cleared environment does not hand
    # a command that valgrind reads: the directory it loads its
    # own tools from, the options a site sets for every run, and
    # the debuginfod servers that give it the debug information of
    # a library it has no copy of.
    # @return [Array<String>]
    ENVIRONMENT = %w[VALGRIND_LIB VALGRIND_OPTS DEBUGINFOD_URLS].freeze

    name "unix-valgrind"
    description "Run a program under valgrind\n" \
                "This command (valgrind) is spawned without a shell, " \
                "and its report is written to stderr"
    parameter :program, String, "the executable to run under valgrind (eg ./a.out)"
    parameter :arguments, Array[String], "the arguments the program is given"
    parameter :tool, Enum[*TOOLS], "the valgrind tool to run"
    parameter :leak_check, Enum[*LEAK_CHECKS], "when to report a leak (memcheck only)"
    parameter :show_leak_kinds, Array[String], "the kinds of leak to report (memcheck only)"
    parameter :track_origins, Boolean, "track the origin of an uninitialised value (memcheck only)"
    parameter :num_callers, Integer, "the number of stack frames to show (2-500)"
    parameter :error_exitcode, Integer, "the exit status valgrind uses when it finds an error"
    parameter :timeout, Integer, "the maximum allowed time for the command to run (in seconds)"
    parameter :max_bytes, Integer, "max number of bytes to emit"
    required %i[program]
    defaults arguments: [], tool: "memcheck", leak_check: nil, show_leak_kinds: [],
             track_origins: false, num_callers: nil, error_exitcode: 1,
             timeout: 300, max_bytes: -> { max_bytes }

    ##
    # @param [String] program
    #  The executable to run under valgrind
    # @param [Array<String>] arguments
    #  The arguments the program is given
    # @param [String] tool
    #  The valgrind tool to run, one of {TOOLS}
    # @param [String, nil] leak_check
    #  When to report a leak, one of {LEAK_CHECKS}
    # @param [Array<String>] show_leak_kinds
    #  The kinds of leak to report, one or more of {LEAK_KINDS}
    # @param [Boolean] track_origins
    #  Track the origin of an uninitialised value
    # @param [Integer, nil] num_callers
    #  The number of stack frames to show
    # @param [Integer] error_exitcode
    #  The exit status valgrind uses when it finds an error
    # @param [Integer] timeout
    #  The maximum allowed time for valgrind to run, in seconds
    # @param [Integer] max_bytes
    #  The max number of bytes to emit
    # @return [Hash]
    def call(program:, arguments: [], tool: "memcheck", leak_check: nil,
             show_leak_kinds: [], track_origins: false, num_callers: nil,
             error_exitcode: 1, timeout: 300, max_bytes: self.class.max_bytes)
      validate!(program:, tool:, leak_check:, show_leak_kinds:, track_origins:,
                num_callers:, error_exitcode:)
      exec(
        command: "valgrind",
        arguments: argv(
          program:, arguments:, tool:, leak_check:, show_leak_kinds:,
          track_origins:, num_callers:, error_exitcode:
        ),
        env:,
        timeout:,
        max_bytes:
      )
    end

    private

    ##
    # The environment valgrind runs in. A spawned command inherits
    # $PATH and nothing else, so the variables valgrind reads are
    # forwarded when they are set.
    # @return [Hash]
    def env
      ENVIRONMENT.each_with_object({}) do |key, env|
        value = ENV[key].to_s
        env[key] = value unless value.empty?
      end
    end

    ##
    # Builds the argument vector valgrind is given: the tool, the
    # memcheck options, the error exit status, `--`, the program,
    # then the arguments of the program.
    # @return [Array<String>]
    def argv(program:, arguments:, tool:, leak_check:, show_leak_kinds:,
             track_origins:, num_callers:, error_exitcode:)
      kinds = Array(show_leak_kinds).join(",")
      [
        "--tool=#{tool}",
        *(leak_check ? ["--leak-check=#{leak_check}"] : []),
        *(kinds.empty? ? [] : ["--show-leak-kinds=#{kinds}"]),
        *(track_origins ? ["--track-origins=yes"] : []),
        *(num_callers ? ["--num-callers=#{num_callers}"] : []),
        "--error-exitcode=#{error_exitcode}",
        "--",
        program,
        *Array(arguments)
      ]
    end

    ##
    # @api private
    def memcheck?(tool)
      tool.to_s == "memcheck"
    end

    ##
    # @api private
    def validate!(program:, tool:, leak_check:, show_leak_kinds:, track_origins:,
                  num_callers:, error_exitcode:)
      if program.to_s.empty?
        raise RuntimeError, "program must be an executable"
      elsif program.to_s.start_with?("-")
        raise RuntimeError, "program must be a path that doesn't begin with '-'"
      elsif !TOOLS.include?(tool.to_s)
        raise RuntimeError, "tool must be one of: #{TOOLS.join(', ')}"
      elsif !memcheck?(tool) && (leak_check || Array(show_leak_kinds).any? || track_origins)
        raise RuntimeError, "leak_check, show_leak_kinds and track_origins are memcheck options"
      elsif leak_check && !LEAK_CHECKS.include?(leak_check.to_s)
        raise RuntimeError, "leak_check must be one of: #{LEAK_CHECKS.join(', ')}"
      elsif blank?(show_leak_kinds)
        raise RuntimeError, "a leak kind can't be empty"
      elsif Array(show_leak_kinds).any? { !LEAK_KINDS.include?(_1.to_s) }
        raise RuntimeError, "a leak kind must be one of: #{LEAK_KINDS.join(', ')}"
      elsif num_callers && (!(::Integer === num_callers) || num_callers < 2 || num_callers > 500)
        raise RuntimeError, "num_callers must be an integer between 2 and 500"
      elsif !(::Integer === error_exitcode) || error_exitcode < 0 || error_exitcode > 255
        raise RuntimeError, "error_exitcode must be an integer between 0 and 255"
      end
    end

    ##
    # @api private
    def blank?(values)
      Array(values).any? { _1.to_s.empty? }
    end
  end
end
