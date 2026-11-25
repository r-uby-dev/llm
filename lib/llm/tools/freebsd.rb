# frozen_string_literal: true

class LLM::Tool
  ##
  # The superclass of all FreeBSD tools.
  #
  # A FreeBSD tool is a tool that works only on
  # FreeBSD - a command that FreeBSD ships and the
  # other systems do not, or a facility that only
  # exists there. `truss` is the first: FreeBSD traces
  # a process with it, Linux traces with `strace` and
  # macOS with `dtruss`, and the three do not share an
  # argument vector. `pkg` is the second: it is how
  # FreeBSD installs software from a repository, where
  # the other systems have their own package managers,
  # so the tools below it are named after the
  # subcommands that answer a question - `pkg search`
  # before `pkg install`. `sh` is the third: it is
  # FreeBSD's shell, a POSIX sh with a few Berkeley
  # extensions, and it is the one command here that
  # takes a script instead of an argv. `objdump` is the
  # fourth, and it makes the point of `truss` again:
  # FreeBSD ships LLVM's dumper where a Linux box ships
  # GNU's, and the two do not take the same arguments.
  #
  # Tools that work anywhere are not FreeBSD tools even
  # when they are named after a command that began
  # there. They live at the top level, and
  # {LLM::Tool::Unix} is the namespace for the ones a
  # unix-like system ships whatever its flavour.
  #
  # @abstract
  # @see LLM::Tool.freebsd
  # @see LLM::Tool::FreeBSD::ObjDump
  # @see LLM::Tool::FreeBSD::PkgInstall
  # @see LLM::Tool::FreeBSD::PkgSearch
  # @see LLM::Tool::FreeBSD::ProcStat
  # @see LLM::Tool::FreeBSD::Sh
  # @see LLM::Tool::FreeBSD::SockStat
  # @see LLM::Tool::FreeBSD::Truss
  class FreeBSD < self
    abstract!

    require_relative "utils/process"
    include LLM::Tool::Utils::Process

    require_relative "freebsd/objdump"
    require_relative "freebsd/pkg_install"
    require_relative "freebsd/pkg_search"
    require_relative "freebsd/proc-stat"
    require_relative "freebsd/sh"
    require_relative "freebsd/sockstat"
    require_relative "freebsd/truss"
  end
end
