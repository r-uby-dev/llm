# frozen_string_literal: true

class LLM::Tool
  ##
  # The superclass of all BSD tools.
  #
  # A BSD tool is a tool that works only on a BSD - a
  # command that FreeBSD ships and the other systems do
  # not, or a facility that only exists there. `truss`
  # is the first: FreeBSD traces a process with it,
  # Linux traces with `strace` and macOS with `dtruss`,
  # and the three do not share an argument vector. `pkg`
  # is the second: it is how a BSD installs software
  # from a repository, where the other systems have
  # their own package managers, so the tools below it are
  # named after the subcommands that answer a question -
  # `pkg search` before `pkg install`. `sockstat` is the
  # third: FreeBSD lists the open sockets with it, Linux
  # with `ss` and macOS with `lsof -i`. `sh` is the
  # fourth: it is FreeBSD's shell, a POSIX sh with a few
  # Berkeley extensions, and it is the one command here
  # that takes a script instead of an argv.
  #
  # Tools that work anywhere are not BSD tools even when
  # they are named after a command that began there.
  # They live at the top level, and {LLM::Tool::Unix} is
  # the namespace for the ones a unix-like system ships
  # whatever its flavour.
  #
  # @abstract
  # @see LLM::Tool.freebsd
  # @see LLM::Tool::BSD::PkgInstall
  # @see LLM::Tool::BSD::PkgSearch
  # @see LLM::Tool::BSD::Sh
  # @see LLM::Tool::BSD::SockStat
  # @see LLM::Tool::BSD::Truss
  class BSD < self
    abstract!

    require_relative "utils/process"
    include LLM::Tool::Utils::Process

    require_relative "bsd/pkg_install"
    require_relative "bsd/pkg_search"
    require_relative "bsd/sh"
    require_relative "bsd/sockstat"
    require_relative "bsd/truss"
  end
end
