# frozen_string_literal: true

require_relative "../unix"

class LLM::Tool::Unix
  ##
  # The {LLM::Tool::Unix::Man LLM::Tool::Unix::Man}
  # class implements a tool that reads a manual page.
  # The page is read as text rather than opened in a
  # pager, so it can be handed to a model.
  #
  # The tool spawns `man` with `-P cat`, which writes
  # the page to stdout where the tool captures it, and
  # it forwards $MANPATH when it is set. It lets an
  # agent read the documentation of a command or a
  # library function it is about to use, eg
  # `man(name: "printf", section: 3)`.
  class Man < self
    require_relative "../exec"

    name "man"
    description "Read a manual page\n" \
                "This command (man) is spawned without a shell"
    parameter :name, String, "the name of the manual page (eg 'printf')"
    parameter :section, Integer, "the section the manual page belongs to (eg 3)"
    parameter :timeout, Integer, "the maximum allowed time for the command to run (in seconds)"
    parameter :max_bytes, Integer, "max number of bytes to emit"
    required %i[name]
    defaults section: nil, timeout: 5, max_bytes: -> { Exec.max_bytes }

    ##
    # @param [String] name
    #  The name of the manual page
    # @param [Integer, nil] section
    #  The section the manual page belongs to
    # @param [Integer] timeout
    #  The maximum allowed time for man to run, in
    #  seconds
    # @param [Integer] max_bytes
    #  The max number of bytes to emit
    # @return [Hash]
    def call(name:, section: nil, timeout: 5, max_bytes: Exec.max_bytes)
      validate!(name:, section:)
      res = Exec.new(env:).call(
        command: "man",
        arguments: ["-P", "cat", *[section, name].compact.map(&:to_s)],
        timeout:,
        max_bytes:
      )
      res[:ok] ? res.merge(stdout: plain(res[:stdout])) : res
    end

    private

    ##
    # The environment the command runs in. The
    # environment of a spawned command is cleared, so
    # $MANPATH is forwarded when it is set, and when it
    # is not, man uses its own search path.
    # @return [Hash]
    def env
      manpath = ENV["MANPATH"].to_s
      manpath.empty? ? {} : {"MANPATH" => manpath}
    end

    ##
    # man writes a bold or an underlined character as
    # the character, a backspace, and the character
    # again, which a pager renders and a reader of the
    # raw output does not. There is no pager here, so
    # the overstrikes are collapsed to plain text.
    # @param [String] text
    # @return [String]
    def plain(text)
      text.to_s.gsub(/.\x08/, "")
    end

    ##
    # @api private
    def validate!(name:, section:)
      if !name.to_s.match?(%r{\A[A-Za-z0-9_.+-]+\z})
        raise RuntimeError, "name must be the name of a manual page (eg 'printf')"
      elsif section && (!(::Integer === section) || section < 1)
        raise RuntimeError, "section must be a positive integer"
      end
    end
  end
end
