# frozen_string_literal: true

require_relative "../unix"

class LLM::Tool::Unix
  ##
  # The
  # {LLM::Tool::Unix::Apropos LLM::Tool::Unix::Apropos}
  # class implements a tool that searches the manual
  # page databases for keywords. It is the step before
  # {LLM::Tool::Unix::Man} - an agent that does not
  # know the name of a page searches the descriptions
  # for a word, and reads the page the search names, eg
  # `apropos(keywords: ["socket"])`.
  #
  # The tool spawns `apropos` without a shell. Each
  # keyword is a term of its own, so two keywords are
  # matched with "or" unless a term carries the macro
  # key syntax of `apropos(1)`, eg `Va=optind`.
  class Apropos < self
    name "apropos"
    description "Search the manual pages for one or more keywords\n" \
                "This command (apropos) is spawned without a shell"
    parameter :keywords, Array[String], "one or more keywords to search for"
    parameter :section, Integer, "the section the manual pages belong to (eg 3)"
    parameter :timeout, Integer, "the maximum allowed time for the command to run (in seconds)"
    parameter :max_bytes, Integer, "max number of bytes to emit"
    required %i[keywords]
    defaults section: nil, timeout: 5, max_bytes: -> { max_bytes }

    ##
    # @param [Array<String>] keywords
    #  One or more keywords to search for
    # @param [Integer, nil] section
    #  The section the manual pages belong to
    # @param [Integer] timeout
    #  The maximum allowed time for apropos to run, in
    #  seconds
    # @param [Integer] max_bytes
    #  The max number of bytes to emit
    # @return [Hash]
    def call(keywords:, section: nil, timeout: 5, max_bytes: self.class.max_bytes)
      validate!(keywords:, section:)
      exec(
        command: "apropos",
        arguments: [*section_arguments(section), "--", *keywords],
        env:,
        timeout:,
        max_bytes:
      )
    end

    private

    ##
    # The environment the command runs in. The
    # environment of a spawned command is cleared, so
    # $MANPATH is forwarded when it is set, and when it
    # is not, apropos uses its own search path.
    # @return [Hash]
    def env
      manpath = ENV["MANPATH"].to_s
      manpath.empty? ? {} : {"MANPATH" => manpath}
    end

    ##
    # @api private
    # @param [Integer, nil] section
    # @return [Array<String>]
    def section_arguments(section)
      section ? ["-s", section.to_s] : []
    end

    ##
    # @api private
    def validate!(keywords:, section:)
      if [*keywords].empty? || [*keywords].any? { _1.to_s.strip.empty? }
        raise RuntimeError, "keywords must be one or more non-empty keywords"
      elsif section && (!(::Integer === section) || section < 1)
        raise RuntimeError, "section must be a positive integer"
      end
    end
  end
end
