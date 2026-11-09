# frozen_string_literal: true

class LLM::Paint
  ##
  # The {LLM::Paint::IO} class wraps an IO so that the text
  # written to it is wrapped in the escape sequences a terminal
  # understands, but only when the wrapped IO is a terminal and
  # {LLM::Paint} is enabled. Otherwise the text is written
  # unchanged.
  #
  # @example
  #   io = LLM::Paint::IO.new(io: $stdout)
  #   io.write("hello", :blue, :bold)
  class IO
    ##
    # @return [IO]
    #  The IO that is wrapped
    attr_reader :io

    ##
    # @param [IO] io
    #  The IO to write to
    # @param [Boolean, nil] color
    #  Enables or disables color. When it is nil, color is
    #  detected from the IO and `$NO_COLOR`.
    # @return [LLM::Paint::IO]
    def initialize(io:, color: nil)
      @io = io
      @color = color.nil? ? LLM::Paint.detect(io) : !!color
    end

    ##
    # @return [Boolean]
    #  True when this IO writes color
    def color?
      @color
    end

    ##
    # Enables or disables color, and when it is given nil it
    # goes back to detecting what the IO supports.
    # @param [Boolean, nil] color
    # @return [void]
    def color=(color)
      @color = color.nil? ? LLM::Paint.detect(@io) : !!color
    end

    ##
    # Writes text to the wrapped IO. The text is wrapped in the
    # escape sequences that represent the given colors and
    # effects when color is enabled, and written unchanged
    # otherwise.
    # @param [String, #to_s] text
    #  The text to write
    # @param [Array<Symbol>] options
    #  A foreground color, a background color, and/or an effect
    # @return [Integer]
    #  The number of bytes written
    def write(text, *options)
      if color?
        @io.write(LLM::Paint[text, *options])
      else
        @io.write(text.to_s)
      end
    end
  end
end
