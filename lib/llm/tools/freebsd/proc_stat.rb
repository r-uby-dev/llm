# frozen_string_literal: true

require_relative "../bsd"

class LLM::Tool::BSD
  ##
  # The {LLM::Tool::BSD::ProcStat LLM::Tool::BSD::ProcStat}
  # class implements a tool that displays detailed process
  # information.
  #
  # It is the question that follows a process nobody can
  # explain: `procstat` answers with the binary behind a
  # pid, the command line it was started with, the
  # environment it inherited, the credentials it runs
  # under, the files it holds open, the signals it has
  # pending, the memory it maps, the threads it runs, and
  # the limits it works within - one subcommand at a time,
  # and one table per call.
  #
  # `command:` picks the subcommand: `args` is the command
  # line, `binary` the path of the executable and the
  # osreldate it was built for, `environment` the
  # environment, `credentials` the uids, the gids, the
  # umask and whether the process is in capability mode,
  # `files` the file descriptors with their type, flags,
  # offset and path, `vm` the virtual memory mappings with
  # their protection flags, `signals` and `tsignals` the
  # pending and the blocked signals, `threads` the threads
  # with the CPU and the state of each, `rlimit` the
  # resource limits, `rusage` the resource usage, `cpuset`
  # the set of CPUs a thread may run on, `kstack` the
  # kernel stacks, `auxv` the ELF auxiliary vector, and
  # `basic` the summary that procstat prints when it is
  # given no subcommand at all. The tool passes the
  # subcommand as its flag, in the order the page lists
  # it, so `files` is `procstat -f` and `credentials` is
  # `procstat -s`.
  #
  # Four subcommands are not exposed. `advlock`, `kqueue`
  # and `rlimitusage` have no single-letter flag, so they
  # cannot be reached without also passing a word, and
  # `ptlwpinfo` reads a core file. Neither are `pargs`,
  # `penv` and `pwdx`: they are separate programs that
  # wrap one subcommand each, and `args`, `environment` and
  # the `cwd` row of `files` answer the same questions.
  #
  # `pids:` is the list of processes to ask about, and
  # `all:` (`-a`) is every process on the system, which is
  # how a model looks without knowing a pid first. The two
  # are mutually exclusive. `headers:` keeps the header
  # line of the table, where `-h` is what turns it off.
  # Three flags follow one subcommand each:
  # `capabilities:` (`-C`) asks `files` for the capability
  # rights of a descriptor rather than its vnode type,
  # `signal_numbers:` (`-n`) asks `signals` or `tsignals`
  # for numbers rather than names, and `per_thread:`
  # (`-H`) asks `rusage` for a row per thread. The tool
  # refuses one of the three on any other subcommand
  # rather than let it be ignored.
  #
  # The information that belongs to a process - the file
  # descriptors, the vm mappings and the cpuset - is
  # available to the owner of the process and the superuser
  # only, so an empty table is a permission question as
  # often as it is an empty answer. `-w` is not exposed:
  # it repeats the output at an interval, and a tool call
  # should return. A core file is not exposed either.
  # The result of {LLM::Tool::Utils::Process#exec} is
  # returned as it is, so a pid that is gone comes back
  # as the exit status of procstat with the stderr that
  # carries it.
  class ProcStat < self
    ##
    # The subcommands, keyed by the name a model asks for,
    # with the flag procstat is given for each of them.
    # `basic` has no flag: it is what procstat prints when
    # no subcommand is given.
    # @return [Hash{String => Array<String>}]
    COMMANDS = {
      "basic" => [],
      "args" => ["-c"],
      "binary" => ["-b"],
      "credentials" => ["-s"],
      "environment" => ["-e"],
      "files" => ["-f"],
      "signals" => ["-i"],
      "tsignals" => ["-j"],
      "threads" => ["-t"],
      "vm" => ["-v"],
      "rlimit" => ["-l"],
      "rusage" => ["-r"],
      "auxv" => ["-x"],
      "cpuset" => ["-S"],
      "kstack" => ["-k"]
    }.freeze

    name "procstat"
    description "Display detailed process information with procstat (FreeBSD)\n" \
                "This command (procstat) is spawned without a shell"
    parameter :command, Enum[*COMMANDS.keys], "the subcommand to ask, eg files, vm or credentials"
    parameter :pids, Array[Integer], "the processes to ask about, by pid"
    parameter :all, Boolean, "ask about every process on the system (-a)"
    parameter :headers, Boolean, "print the header line of the table (-h turns this off)"
    parameter :capabilities, Boolean, "ask files for the capability rights of a descriptor (-C)"
    parameter :signal_numbers, Boolean, "ask signals or tsignals for numbers, not names (-n)"
    parameter :per_thread, Boolean, "ask rusage for a row per thread (-H)"
    parameter :timeout, Integer, "the maximum allowed time for the command to run (in seconds)"
    parameter :max_bytes, Integer, "max number of bytes to emit"
    defaults command: "basic", pids: [], all: false, headers: true,
             capabilities: false, signal_numbers: false, per_thread: false,
             timeout: 30, max_bytes: -> { max_bytes }

    ##
    # @param [String] command
    #  The subcommand to ask, one of {COMMANDS}
    # @param [Array<Integer>] pids
    #  The processes to ask about, by pid
    # @param [Boolean] all
    #  Ask about every process on the system
    # @param [Boolean] headers
    #  Print the header line of the table
    # @param [Boolean] capabilities
    #  Ask `files` for the capability rights of a
    #  descriptor rather than its vnode type
    # @param [Boolean] signal_numbers
    #  Ask `signals` or `tsignals` for numbers rather than
    #  names
    # @param [Boolean] per_thread
    #  Ask `rusage` for a row per thread
    # @param [Integer] timeout
    #  The maximum allowed time for procstat to run, in
    #  seconds
    # @param [Integer] max_bytes
    #  The max number of bytes to emit
    # @return [Hash]
    def call(command: "basic", pids: [], all: false, headers: true, capabilities: false,
             signal_numbers: false, per_thread: false, timeout: 30,
             max_bytes: self.class.max_bytes)
      validate!(command:, pids:, all:, capabilities:, signal_numbers:, per_thread:)
      exec(
        command: "procstat",
        arguments: arguments(
          command:, pids:, all:, headers:, capabilities:, signal_numbers:, per_thread:
        ),
        timeout:,
        max_bytes:
      )
    end

    private

    ##
    # Builds the argument vector procstat is given: `-a`,
    # `-h`, the three flags that follow one subcommand, the
    # subcommand itself, then the pids.
    # @return [Array<String>]
    def arguments(command:, pids:, all:, headers:, capabilities:, signal_numbers:, per_thread:)
      [
        *(all ? ["-a"] : []),
        *(headers ? [] : ["-h"]),
        *(capabilities ? ["-C"] : []),
        *(signal_numbers ? ["-n"] : []),
        *(per_thread ? ["-H"] : []),
        *COMMANDS.fetch(command.to_s),
        *Array(pids).map(&:to_s)
      ]
    end

    ##
    # @api private
    def validate!(command:, pids:, all:, capabilities:, signal_numbers:, per_thread:)
      if !COMMANDS.key?(command.to_s)
        raise RuntimeError, "command must be one of: #{COMMANDS.keys.join(', ')}"
      elsif all && Array(pids).any?
        raise RuntimeError, "all and pids are mutually exclusive"
      elsif !all && Array(pids).empty?
        raise RuntimeError, "a pid or all is required"
      elsif Array(pids).any? { |pid| !(::Integer === pid) || pid < 1 }
        raise RuntimeError, "a pid must be a positive integer"
      elsif capabilities && command.to_s != "files"
        raise RuntimeError, "capabilities needs the files command"
      elsif signal_numbers && !%w[signals tsignals].include?(command.to_s)
        raise RuntimeError, "signal_numbers needs the signals or tsignals command"
      elsif per_thread && command.to_s != "rusage"
        raise RuntimeError, "per_thread needs the rusage command"
      end
    end
  end
end
