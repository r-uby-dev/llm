# frozen_string_literal: true

require_relative "../bsd"

class LLM::Tool::BSD
  ##
  # The {LLM::Tool::BSD::Sh LLM::Tool::BSD::Sh} class
  # implements a tool that runs a shell script.
  #
  # It spawns `sh` with the whole script as the single
  # operand of `-c`, so the chaining, the pipes and the
  # directory changes happen inside one process:
  # `cd /usr/src && make -j8` is one call here, and a
  # sequence of calls with a tool for each step
  # otherwise. Nothing is re-parsed on the way in - the
  # script arrives as a string, the quoting is the
  # script's business, and a path that begins with `-`
  # has no `--` to hide behind. That is the trade for
  # {LLM::Tool::Exec} and the per-command tools, which
  # pass an argv vector that never sees a shell.
  #
  # The flags are sh(1)'s, in its order: `noclobber:`
  # (`-C`) keeps `>` from overwriting a file,
  # `errexit:` (`-e`) exits on an untested failure -
  # the page warns that many commands return non-zero
  # to convey something other than an error -
  # `noglob:` (`-f`) turns pathname expansion off,
  # `noexec:` (`-n`) reads the script and runs nothing,
  # `physical:` (`-P`) moves `cd` and `pwd` to the
  # physical directory, `nounset:` (`-u`) exits on an
  # unset variable, and `xtrace:` (`-x`) and
  # `verbose:` (`-v`) write the trace and the input to
  # stderr. `pipefail:` has no single letter - it is
  # `-o pipefail` - and it makes a pipeline's exit
  # status the last non-zero one. Privileged mode (`-p`)
  # is deliberately not exposed. The result of
  # {LLM::Tool::Utils::Process#exec} is returned as it
  # is, and `timeout:` is what stops a loop that would
  # not end on its own.
  class Sh < self
    name "sh"
    description "Run a script with sh (FreeBSD)\n" \
                "This command (sh) is given its script with -c"
    parameter :script, String, "the script to run, as one string (-c)"
    parameter :errexit, Boolean, "exit if an untested command fails (-e)"
    parameter :nounset, Boolean, "exit when an unset variable is expanded (-u)"
    parameter :noexec, Boolean, "read the script but run nothing (-n)"
    parameter :xtrace, Boolean, "write each command to stderr before running it (-x)"
    parameter :verbose, Boolean, "write the input to stderr as it is read (-v)"
    parameter :noclobber, Boolean, "do not overwrite an existing file with > (-C)"
    parameter :noglob, Boolean, "turn pathname expansion off (-f)"
    parameter :physical, Boolean, "make cd and pwd physical rather than logical (-P)"
    parameter :pipefail, Boolean, "use the last non-zero exit status of a pipeline (-o pipefail)"
    parameter :timeout, Integer, "the maximum allowed time for the command to run (in seconds)"
    parameter :max_bytes, Integer, "max number of bytes to emit"
    required %i[script]
    defaults errexit: false, nounset: false, noexec: false, xtrace: false,
             verbose: false, noclobber: false, noglob: false, physical: false,
             pipefail: false, timeout: 30, max_bytes: -> { max_bytes }

    ##
    # @param [String] script
    #  The script to run, as one string
    # @param [Boolean] errexit
    #  Exit if an untested command fails
    # @param [Boolean] nounset
    #  Exit when an unset variable is expanded
    # @param [Boolean] noexec
    #  Read the script but run nothing
    # @param [Boolean] xtrace
    #  Write each command to stderr before running it
    # @param [Boolean] verbose
    #  Write the input to stderr as it is read
    # @param [Boolean] noclobber
    #  Do not overwrite an existing file with `>`
    # @param [Boolean] noglob
    #  Turn pathname expansion off
    # @param [Boolean] physical
    #  Make `cd` and `pwd` physical rather than logical
    # @param [Boolean] pipefail
    #  Use the last non-zero exit status of a pipeline
    # @param [Integer] timeout
    #  The maximum allowed time for sh to run, in
    #  seconds
    # @param [Integer] max_bytes
    #  The max number of bytes to emit
    # @return [Hash]
    def call(script:, errexit: false, nounset: false, noexec: false, xtrace: false,
             verbose: false, noclobber: false, noglob: false, physical: false,
             pipefail: false, timeout: 30, max_bytes: self.class.max_bytes)
      validate!(script:)
      exec(
        command: "sh",
        arguments: arguments(
          script:, errexit:, nounset:, noexec:, xtrace:, verbose:,
          noclobber:, noglob:, physical:, pipefail:
        ),
        timeout:,
        max_bytes:
      )
    end

    private

    ##
    # Builds the argument vector sh is given: the flags
    # in the order sh(1) lists them, `-c`, then the
    # script, which is the one operand `-c` takes.
    # @return [Array<String>]
    def arguments(script:, errexit:, nounset:, noexec:, xtrace:, verbose:,
                  noclobber:, noglob:, physical:, pipefail:)
      [
        *(noclobber ? ["-C"] : []),
        *(errexit ? ["-e"] : []),
        *(noglob ? ["-f"] : []),
        *(noexec ? ["-n"] : []),
        *(physical ? ["-P"] : []),
        *(nounset ? ["-u"] : []),
        *(verbose ? ["-v"] : []),
        *(xtrace ? ["-x"] : []),
        *(pipefail ? ["-o", "pipefail"] : []),
        "-c",
        script
      ]
    end

    ##
    # @api private
    def validate!(script:)
      if script.to_s.strip.empty?
        raise RuntimeError, "script can't be empty"
      elsif script.to_s.include?("\0")
        raise RuntimeError, "a script can't contain a NUL character"
      end
    end
  end
end
