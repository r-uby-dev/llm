# frozen_string_literal: true

require_relative "../unix"

class LLM::Tool::Unix
  ##
  # The {LLM::Tool::Unix::Uname LLM::Tool::Unix::Uname}
  # class implements a tool that reports what the system
  # is.
  #
  # It spawns `uname` without a shell and it sticks to
  # the POSIX options - `-s` for the kernel name, `-n`
  # for the node name, `-r` for the kernel release, `-v`
  # for the version, `-m` for the machine - plus `-a`,
  # which is the five of them at once. They mean the same
  # thing on FreeBSD, Linux and macOS, which is what lets
  # this live in {LLM::Tool::Unix}.
  #
  # The FreeBSD extensions are deliberately absent. `-p`
  # is the processor architecture there but "unknown" on
  # Linux, `-i` is the kernel ident there and the hardware
  # platform on Linux, and `-K`, `-U` and `-b` are FreeBSD
  # only. A model that needs those asks a BSD tool for
  # them. With no flag at all `uname` prints the kernel
  # name, and several flags print on one line, separated
  # by spaces.
  #
  # uname(1) lets the environment rewrite an answer -
  # `UNAME_s` for `-s` and so on, `-a` excepted - and the
  # child here inherits $PATH and nothing else, so the
  # environment of this process cannot put a different
  # name in the result. The result of
  # {LLM::Tool::Utils::Process#exec} is returned as it
  # is.
  class Uname < self
    name "uname"
    description "Report what the system is (POSIX)\n" \
                "This command (uname) is spawned without a shell"
    parameter :kernel, Boolean, "the name of the operating system implementation (-s)"
    parameter :nodename, Boolean, "the name of the system (-n)"
    parameter :release, Boolean, "the current release level of the kernel (-r)"
    parameter :version, Boolean, "the version level of this release (-v)"
    parameter :machine, Boolean, "the type of the current hardware platform (-m)"
    parameter :all, Boolean, "every one of the above on one line (-a)"
    parameter :timeout, Integer, "the maximum allowed time for the command to run (in seconds)"
    parameter :max_bytes, Integer, "max number of bytes to emit"
    defaults kernel: false, nodename: false, release: false, version: false,
             machine: false, all: false, timeout: 5, max_bytes: -> { max_bytes }

    ##
    # @param [Boolean] kernel
    #  The name of the operating system implementation
    # @param [Boolean] nodename
    #  The name of the system
    # @param [Boolean] release
    #  The current release level of the kernel
    # @param [Boolean] version
    #  The version level of this release
    # @param [Boolean] machine
    #  The type of the current hardware platform
    # @param [Boolean] all
    #  Every one of the above, on one line
    # @param [Integer] timeout
    #  The maximum allowed time for uname to run, in
    #  seconds
    # @param [Integer] max_bytes
    #  The max number of bytes to emit
    # @return [Hash]
    def call(kernel: false, nodename: false, release: false, version: false,
             machine: false, all: false, timeout: 5,
             max_bytes: self.class.max_bytes)
      exec(
        command: "uname",
        arguments: arguments(
          kernel:, nodename:, release:, version:, machine:, all:
        ),
        timeout:,
        max_bytes:
      )
    end

    private

    ##
    # Builds the argument vector uname is given, in the
    # order uname(1) lists the flags. `-a` is the five
    # flags at once, so it is passed on its own.
    # @return [Array<String>]
    def arguments(kernel:, nodename:, release:, version:, machine:, all:)
      return ["-a"] if all
      [
        *(machine ? ["-m"] : []),
        *(nodename ? ["-n"] : []),
        *(release ? ["-r"] : []),
        *(kernel ? ["-s"] : []),
        *(version ? ["-v"] : [])
      ]
    end
  end
end
