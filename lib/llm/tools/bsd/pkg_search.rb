# frozen_string_literal: true

require_relative "../bsd"

class LLM::Tool::BSD
  ##
  # The {LLM::Tool::BSD::PkgSearch LLM::Tool::BSD::PkgSearch}
  # class implements a tool that searches the FreeBSD
  # package repository for the name of a package.
  #
  # It asks `pkg search`, which matches the short
  # description of a package, a name and a maintainer
  # alike. It is the tool that {LLM::Tool::BSD::PkgInstall}
  # runs after: a model that does not know what a package
  # is called searches for it, and installs the name the
  # search gives.
  #
  # The tool spawns `pkg search` without a shell, the
  # term comes after `--`, and the result is returned as
  # it is.
  #
  # The result of {LLM::Tool::Utils::Process#exec} is
  # returned as it is.
  class PkgSearch < self
    name "pkg-search"
    description "Search the FreeBSD package repository for a package\n" \
                "This command (pkg search) is spawned without a shell"
    parameter :term, String, "the text to search for"
    parameter :timeout, Integer, "the maximum allowed time for the command to run (in seconds)"
    parameter :max_bytes, Integer, "max number of bytes to emit"
    required %i[term]
    defaults timeout: 20, max_bytes: -> { max_bytes }

    ##
    # @param [String] term
    #  The text to search for
    # @param [Integer] timeout
    #  The maximum allowed time for pkg to run, in
    #  seconds
    # @param [Integer] max_bytes
    #  The max number of bytes to emit
    # @return [Hash]
    def call(term:, timeout: 20, max_bytes: self.class.max_bytes)
      validate!(term:)
      exec(
        command: "pkg",
        arguments: ["search", "--", term],
        timeout:,
        max_bytes:
      )
    end

    ##
    # @api private
    def validate!(term:)
      if term.to_s.empty?
        raise RuntimeError, "term can't be empty"
      elsif term.to_s.start_with?("-")
        raise RuntimeError, "a term can't begin with '-'"
      end
    end
  end
end
