# frozen_string_literal: true

require_relative "../unix"

class LLM::Tool::Unix
  ##
  # The {LLM::Tool::Unix::HonggFuzz LLM::Tool::Unix::HonggFuzz} class
  # implements a tool that fuzzes a program with honggfuzz.
  #
  # It spawns `honggfuzz` without a shell, and it builds the argument
  # vector itself: the flags, then `--`, then the program and the
  # arguments the program is fuzzed with. Everything after `--` belongs
  # to the program, so a flag of the program is never read as a flag of
  # honggfuzz, and nothing after `--` is the one thing honggfuzz refuses
  # to run without.
  #
  # honggfuzz mutates a file and tells the program where it is by
  # replacing `___FILE___` in the program's arguments, which is why
  # {FILE} is the default of `arguments:`. With `stdin: true` (`-s`) the
  # input arrives on stdin instead, and a default `arguments:` is dropped
  # rather than left as a placeholder the program would receive as a
  # literal path.
  #
  # honggfuzz runs until it is killed, so every call is bounded by
  # `timeout:` - 120 seconds unless it is given - or by `iterations:`
  # (`-N`, unlimited at 0). A killed run is not a failed one: the result
  # is what honggfuzz logged before it died, and the note that
  # {LLM::Tool::Utils::Process#exec} adds says the output is probably
  # incomplete. A model that wants a longer run asks for a longer
  # `timeout:` or for a number of iterations.
  #
  # Two defaults differ from the ones honggfuzz ships with because the
  # reader is a model: `nullify_stdio: true` (`-q`) so the program cannot
  # bury the log in its own output, and `plain: true` (`-v`) so the log
  # has no ANSI escape sequences once it is captured. What a run finds is
  # written where honggfuzz writes it, so the follow up is ordinary: the
  # crashes and the runtime files are in `workspace:` (`-W`), the report
  # is in `report:` (`-R`, `HONGGFUZZ.REPORT.TXT` in the working
  # directory when it is not given), and {LLM::Tool::Unix::Ls},
  # {LLM::Tool::ReadFile} and {LLM::Tool::Unix::Cat} read them.
  #
  # Every value is validated before anything is spawned: an empty value,
  # or one that begins with `-`, is rejected, so a path is never read as
  # a flag of its own - while an argument of the program may begin with
  # `-`, because it comes after `--`.
  class HonggFuzz < self
    ##
    # The placeholder honggfuzz replaces with the path of the input the
    # program is given.
    # @return [String]
    FILE = "___FILE___"

    ##
    # The debug levels honggfuzz accepts, from `0` (FATAL) to `4`
    # (DEBUG).
    # @return [Array<String>]
    LEVELS = %w[0 1 2 3 4].freeze

    name "unix-honggfuzz"
    description "Fuzz a program with honggfuzz\n" \
                "honggfuzz is spawned without a shell and runs until it is killed"
    parameter :command, String, "the program to fuzz"
    parameter :arguments, Array[String], "the arguments the program is given, with #{FILE} where the input goes"
    parameter :input, String, "the corpus file or directory the inputs come from (-f)"
    parameter :workspace, String, "the directory crashes and runtime files are saved in (-W)"
    parameter :stdin, Boolean, "put the input on stdin instead of in a file (-s)"
    parameter :threads, Integer, "the number of fuzzing threads (-n)"
    parameter :iterations, Integer, "the number of fuzzing iterations, unlimited at 0 (-N)"
    parameter :child_timeout, Integer, "the number of seconds one fuzzed process may run (-t)"
    parameter :max_file_size, Integer, "the largest input honggfuzz writes, in bytes (-F)"
    parameter :extension, String, "the extension of the input files, eg 'swf' (-e)"
    parameter :wordlist, String, "a wordlist file, with tokens delimited by NUL bytes (-w)"
    parameter :blacklist, String, "a stackhash blacklist file, one entry per line (-B)"
    parameter :mutator, String, "an external command that mutates the corpus instead of the builtin one (-c)"
    parameter :flip_rate, Number, "the maximal flip rate, between 0 and 1 (-r)"
    parameter :save_all, Boolean, "save every test case, not only the unique ones (-u)"
    parameter :nullify_stdio, Boolean, "nullify the program's stdin, stdout and stderr (-q)"
    parameter :plain, Boolean, "print a plain log without ANSI escape codes (-v)"
    parameter :sancov, Boolean, "enable sanitizer coverage feedback (-C)"
    parameter :debug_level, Enum[*LEVELS], "the debug level, from 0 (FATAL) to 4 (DEBUG) (-d)"
    parameter :report, String, "the file the report is written to (-R)"
    parameter :logfile, String, "the file the log is written to (-l)"
    parameter :environment, Array[String], "NAME=value pairs to put in the program's environment (-E)"
    parameter :clear_environment, Boolean, "clear the environment before the program runs (--clear_env)"
    parameter :memory_limit, Integer, "the per process memory limit, in MiB (--rlimit_as)"
    parameter :timeout, Integer, "the maximum allowed time for the command to run (in seconds)"
    parameter :max_bytes, Integer, "max number of bytes to emit"
    required %i[command]
    defaults arguments: [FILE], input: nil, workspace: nil, stdin: false, threads: nil,
             iterations: nil, child_timeout: nil, max_file_size: nil, extension: nil,
             wordlist: nil, blacklist: nil, mutator: nil, flip_rate: nil, save_all: false,
             nullify_stdio: true, plain: true, sancov: false, debug_level: nil, report: nil,
             logfile: nil, environment: [], clear_environment: false, memory_limit: nil,
             timeout: 120, max_bytes: -> { max_bytes }

    ##
    # @param [String] command
    #  The program to fuzz
    # @param [Array<String>] arguments
    #  The arguments the program is given, with {FILE} where the input
    #  file goes
    # @param [String, nil] input
    #  The corpus file or directory the inputs come from
    # @param [String, nil] workspace
    #  The directory crashes and runtime files are saved in
    # @param [Boolean] stdin
    #  Put the input on stdin instead of in a file
    # @param [Integer, nil] threads
    #  The number of fuzzing threads
    # @param [Integer, nil] iterations
    #  The number of fuzzing iterations, unlimited at 0
    # @param [Integer, nil] child_timeout
    #  The number of seconds one fuzzed process may run
    # @param [Integer, nil] max_file_size
    #  The largest input honggfuzz writes, in bytes
    # @param [String, nil] extension
    #  The extension of the input files
    # @param [String, nil] wordlist
    #  A wordlist file, with tokens delimited by NUL bytes
    # @param [String, nil] blacklist
    #  A stackhash blacklist file, one entry per line
    # @param [String, nil] mutator
    #  An external command that mutates the corpus
    # @param [Numeric, nil] flip_rate
    #  The maximal flip rate, between 0 and 1
    # @param [Boolean] save_all
    #  Save every test case, not only the unique ones
    # @param [Boolean] nullify_stdio
    #  Nullify the program's stdin, stdout and stderr
    # @param [Boolean] plain
    #  Print a plain log without ANSI escape codes
    # @param [Boolean] sancov
    #  Enable sanitizer coverage feedback
    # @param [String, nil] debug_level
    #  The debug level, one of {LEVELS}
    # @param [String, nil] report
    #  The file the report is written to
    # @param [String, nil] logfile
    #  The file the log is written to
    # @param [Array<String>] environment
    #  One or more NAME=value pairs for the program's environment
    # @param [Boolean] clear_environment
    #  Clear the environment before the program runs
    # @param [Integer, nil] memory_limit
    #  The per process memory limit, in MiB
    # @param [Integer] timeout
    #  The max number of seconds to wait for honggfuzz
    # @param [Integer] max_bytes
    #  The max number of bytes to emit
    # @return [Hash]
    def call(command:, arguments: [FILE], input: nil, workspace: nil, stdin: false, threads: nil,
             iterations: nil, child_timeout: nil, max_file_size: nil, extension: nil,
             wordlist: nil, blacklist: nil, mutator: nil, flip_rate: nil, save_all: false,
             nullify_stdio: true, plain: true, sancov: false, debug_level: nil, report: nil,
             logfile: nil, environment: [], clear_environment: false, memory_limit: nil,
             timeout: 120, max_bytes: self.class.max_bytes)
      arguments = Array(arguments)
      arguments = [] if stdin && arguments == [FILE]
      validate!(
        command:, arguments:, input:, workspace:, stdin:, threads:, iterations:, child_timeout:,
        max_file_size:, extension:, wordlist:, blacklist:, mutator:, flip_rate:, report:,
        logfile:, environment:, debug_level:, memory_limit:
      )
      exec(
        command: "honggfuzz",
        arguments: argv(
          command:, arguments:, input:, workspace:, stdin:, threads:, iterations:,
          child_timeout:, max_file_size:, extension:, wordlist:, blacklist:, mutator:,
          flip_rate:, save_all:, nullify_stdio:, plain:, sancov:, debug_level:, report:,
          logfile:, environment:, clear_environment:, memory_limit:
        ),
        timeout:,
        max_bytes:
      )
    end

    private

    ##
    # Builds the argument vector honggfuzz is given: the flags, then
    # `--`, then the program and the arguments it is fuzzed with. The
    # order is fixed so that the same call is the same vector, and `--`
    # sits between the two because everything after it belongs to the
    # program.
    # @return [Array<String>]
    def argv(command:, arguments:, input:, workspace:, stdin:, threads:, iterations:,
             child_timeout:, max_file_size:, extension:, wordlist:, blacklist:, mutator:,
             flip_rate:, save_all:, nullify_stdio:, plain:, sancov:, debug_level:, report:,
             logfile:, environment:, clear_environment:, memory_limit:)
      [
        *(input ? ["-f", input] : []),
        *(workspace ? ["-W", workspace] : []),
        *(stdin ? ["-s"] : []),
        *(threads ? ["-n", threads.to_s] : []),
        *(iterations ? ["-N", iterations.to_s] : []),
        *(child_timeout ? ["-t", child_timeout.to_s] : []),
        *(max_file_size ? ["-F", max_file_size.to_s] : []),
        *(extension ? ["-e", extension] : []),
        *(wordlist ? ["-w", wordlist] : []),
        *(blacklist ? ["-B", blacklist] : []),
        *(mutator ? ["-c", mutator] : []),
        *(flip_rate ? ["-r", flip_rate.to_s] : []),
        *(save_all ? ["-u"] : []),
        *(nullify_stdio ? ["-q"] : []),
        *(plain ? ["-v"] : []),
        *(sancov ? ["-C"] : []),
        *(debug_level ? ["-d", debug_level.to_s] : []),
        *(report ? ["-R", report] : []),
        *(logfile ? ["-l", logfile] : []),
        *Array(environment).flat_map { ["-E", _1.to_s] },
        *(clear_environment ? ["--clear_env"] : []),
        *(memory_limit ? ["--rlimit_as", memory_limit.to_s] : []),
        "--",
        command,
        *Array(arguments)
      ]
    end

    ##
    # @api private
    def validate!(command:, arguments:, input:, workspace:, stdin:, threads:, iterations:,
                  child_timeout:, max_file_size:, extension:, wordlist:, blacklist:, mutator:,
                  flip_rate:, report:, logfile:, environment:, debug_level:, memory_limit:)
      if command.to_s.empty?
        raise RuntimeError, "command must be the program to fuzz"
      elsif command.to_s.start_with?("-")
        raise RuntimeError, "command must be a path that doesn't begin with '-'"
      elsif Array(arguments).any? { _1.to_s.empty? }
        raise RuntimeError, "an argument of the program can't be empty"
      elsif stdin && Array(arguments).include?(FILE)
        raise RuntimeError, "#{FILE} must not appear in arguments when stdin is true"
      elsif !stdin && !Array(arguments).include?(FILE)
        raise RuntimeError, "arguments must include #{FILE} so the input has somewhere to go, " \
                            "or stdin must be true"
      end
      paths!(input:, workspace:, extension:, wordlist:, blacklist:, mutator:, report:, logfile:)
      if threads && (!(::Integer === threads) || threads < 1)
        raise RuntimeError, "threads must be a positive integer"
      elsif iterations && (!(::Integer === iterations) || iterations < 0)
        raise RuntimeError, "iterations must be zero or a positive integer"
      elsif child_timeout && (!(::Integer === child_timeout) || child_timeout < 1)
        raise RuntimeError, "child_timeout must be a positive integer"
      elsif max_file_size && (!(::Integer === max_file_size) || max_file_size < 1)
        raise RuntimeError, "max_file_size must be a positive integer"
      elsif memory_limit && (!(::Integer === memory_limit) || memory_limit < 1)
        raise RuntimeError, "memory_limit must be a positive integer"
      elsif flip_rate && (!(::Numeric === flip_rate) || !(0.0..1.0).cover?(flip_rate))
        raise RuntimeError, "flip_rate must be between 0 and 1"
      elsif debug_level && !LEVELS.include?(debug_level.to_s)
        raise RuntimeError, "debug_level must be one of: #{LEVELS.join(', ')}"
      elsif Array(environment).any? { !_1.to_s.match?(%r{\A[A-Za-z_][A-Za-z0-9_]*=}) }
        raise RuntimeError, "an environment variable must be a NAME=value pair"
      end
    end

    ##
    # A value that is empty, or that begins with `-`, is rejected so that
    # a path is never read as a flag of its own.
    # @api private
    def paths!(**paths)
      paths.each do |name, value|
        next if value.nil?
        if value.to_s.empty?
          raise RuntimeError, "#{name} can't be empty"
        elsif value.to_s.start_with?("-")
          raise RuntimeError, "#{name} must be a value that doesn't begin with '-'"
        end
      end
    end
  end
end
