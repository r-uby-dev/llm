# frozen_string_literal: true

require_relative "../bsd"

class LLM::Tool::BSD
  ##
  # The {LLM::Tool::BSD::Truss LLM::Tool::BSD::Truss}
  # class implements a tool that traces the system calls
  # of a process.
  #
  # It is the question that follows a build that
  # succeeded and a program that fails anyway: what did
  # it ask the kernel for, and which of those calls did
  # the kernel refuse. `truss` writes the trace to the
  # standard error unless `output:` names a file, so the
  # trace arrives through the stderr of
  # {LLM::Tool::Exec} like any other diagnostic.
  #
  # `-f` follows the children the process forks, which
  # is how a shell script or a program that spawns a
  # helper is traced, and `-c` throws the individual
  # calls away for a summary of the time, the count and
  # the errors per system call. `-p` traces a process
  # that is already running, and it cannot be combined
  # with a command.
  #
  # It is a FreeBSD tool. Linux has `strace` and macOS
  # has `dtruss`, and neither of them takes these
  # arguments.
  class Truss < self
    require_relative "../exec"

    name "truss"
    description "Trace the system calls of a process (FreeBSD)\n" \
                "This command (truss) is spawned without a shell"
    parameter :command, String, "the program to run and trace"
    parameter :arguments, Array[String], "one or more arguments for the program"
    parameter :pid, Integer, "trace the running process with this pid instead of a command"
    parameter :follow, Boolean, "trace the children the process forks (-f)"
    parameter :count, Boolean, "summarize the system calls instead of showing each one (-c)"
    parameter :signals, Boolean, "show the signals the process receives (-S turns this off)"
    parameter :output, String, "write the trace to this file instead of the standard error"
    parameter :string_size, Integer, "the max number of characters a string is shown with (-s)"
    parameter :timeout, Integer, "the maximum allowed time for the command to run (in seconds)"
    parameter :max_bytes, Integer, "max number of bytes to emit"
    defaults command: nil, arguments: [], pid: nil, follow: false, count: false,
             signals: true, output: nil, string_size: nil, timeout: 60,
             max_bytes: -> { Exec.max_bytes }

    ##
    # @param [String, nil] command
    #  The program to run and trace
    # @param [Array<String>] arguments
    #  One or more arguments for the program
    # @param [Integer, nil] pid
    #  Trace the running process with this pid instead
    #  of a command
    # @param [Boolean] follow
    #  Trace the children the process forks
    # @param [Boolean] count
    #  Summarize the system calls instead of showing
    #  each one
    # @param [Boolean] signals
    #  Show the signals the process receives
    # @param [String, nil] output
    #  Write the trace to this file instead of the
    #  standard error
    # @param [Integer, nil] string_size
    #  The max number of characters a string is shown
    #  with. truss shows 32 when this is not given
    # @param [Integer] timeout
    #  The maximum allowed time for truss to run, in
    #  seconds
    # @param [Integer] max_bytes
    #  The max number of bytes to emit
    # @return [Hash]
    def call(command: nil, arguments: [], pid: nil, follow: false, count: false,
             signals: true, output: nil, string_size: nil, timeout: 60,
             max_bytes: Exec.max_bytes)
      validate!(command:, pid:, output:, string_size:)
      Exec.new.call(
        command: "truss",
        arguments: arguments(
          command:, arguments:, pid:, follow:, count:, signals:, output:, string_size:
        ),
        timeout:,
        max_bytes:
      )
    end

    private

    ##
    # Builds the argument vector truss is given: the flags,
    # the output file, the string size, then the process
    # it traces - a pid, or a command and its arguments.
    # @return [Array<String>]
    def arguments(command:, arguments:, pid:, follow:, count:, signals:, output:, string_size:)
      [
        *(follow ? ["-f"] : []),
        *(count ? ["-c"] : []),
        *(signals ? [] : ["-S"]),
        *(output ? ["-o", output] : []),
        *(string_size ? ["-s", string_size.to_s] : []),
        *(pid ? ["-p", pid.to_s] : []),
        *(command ? [command, *Array(arguments)] : [])
      ]
    end

    ##
    # @api private
    def validate!(command:, pid:, output:, string_size:)
      if command && pid
        raise RuntimeError, "command and pid are mutually exclusive"
      elsif !command && !pid
        raise RuntimeError, "a command or a pid is required"
      elsif command && command.to_s.empty?
        raise RuntimeError, "a command can't be empty"
      elsif command && command.to_s.start_with?("-")
        raise RuntimeError, "a command can't begin with '-'"
      elsif pid && (!(::Integer === pid) || pid < 1)
        raise RuntimeError, "pid must be a positive integer"
      elsif output && output.to_s.empty?
        raise RuntimeError, "output can't be empty"
      elsif string_size && (!(::Integer === string_size) || string_size < 1)
        raise RuntimeError, "string_size must be a positive integer"
      end
    end
  end
end
