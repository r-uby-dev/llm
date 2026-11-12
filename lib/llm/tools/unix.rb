# frozen_string_literal: true

class LLM::Tool
  ##
  # The superclass of all unix tools.
  #
  # A unix tool is a tool that works only on a unix-like system. It
  # depends on a command Windows does not ship (`apropos`, `find`,
  # `man`, `mkdir`), or on a system facility that only exists there.
  #
  # Tools that work anywhere - reading and writing files, changing
  # directory, spawning a command - are not unix tools even when they
  # are named after a unix command. They live at the top level, and
  # {LLM::Tool::Exec} for example works on Windows too.
  #
  # @abstract
  # @see LLM::Tool.unix
  # @see LLM::Tool::Unix::Apropos
  # @see LLM::Tool::Unix::Find
  # @see LLM::Tool::Unix::Man
  # @see LLM::Tool::Unix::Mkdir
  class Unix < self
    abstract!

    require_relative "unix/apropos"
    require_relative "unix/find"
    require_relative "unix/man"
    require_relative "unix/mkdir"
  end
end
