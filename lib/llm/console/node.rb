# frozen_string_literal: true

class LLM::Console
  ##
  # The {LLM::Console::Node LLM::Console::Node} class wraps a piece
  # of text and optional curses attributes.
  # @api private
  class Node
    ##
    # Returns the display width of the given text, counting wide
    # characters such as emoji as two columns.
    # @param [#to_s] text
    # @return [Integer]
    def self.width(text)
      Unicode::DisplayWidth.of(text.to_s)
    end

    ##
    # Slices the given text so the returned piece has a display width
    # of at most `width` columns.
    # @param [#to_s] text
    # @param [Integer] width
    # @return [String]
    def self.slice(text, width)
      out = +""
      text.to_s.each_char do |char|
        break if self.width(out + char) > width
        out << char
      end
      out
    end

    ##
    # @return [String]
    attr_reader :text

    ##
    # @return [Integer, nil]
    attr_reader :attrs

    ##
    # @param [String] text
    # @param [Integer, nil] attrs
    # @return [LLM::Console::Node]
    def initialize(text, attrs = nil)
      @text = text.to_s
      @attrs = attrs
    end

    ##
    # Returns the display width of the text
    # @return [Integer]
    def size
      self.class.width(@text)
    end
    alias_method :length, :size

    ##
    # Hash-like lookup.
    # @param [Symbol] key
    # @return [String, Integer, nil]
    def [](key)
      case key
      when :text then @text
      when :attrs then @attrs
      end
    end
  end
end
