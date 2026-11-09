# frozen_string_literal: true

##
# Inspired by the paint gem (https://github.com/janlelis/paint).
#
# The MIT LICENSE
#
# Copyright (c) 2011-2025 Jan Lelis
#
# Permission is hereby granted, free of charge, to any person obtaining
# a copy of this software and associated documentation files (the
# "Software"), to deal in the Software without restriction, including
# without limitation the rights to use, copy, modify, merge, publish,
# distribute, sublicense, and/or sell copies of the Software, and to
# permit persons to whom the Software is furnished to do so, subject to
# the following conditions:
#
# The above copyright notice and this permission notice shall be
# included in all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
# EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
# MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
# NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE
# LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION
# OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION
# WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

##
# The {LLM::Paint} class wraps a string in the ANSI escape
# sequences that a terminal understands as color. It returns
# the text it is given, unchanged, when color is disabled.
#
# @example
#   LLM::Paint["hello", :blue]        # => "\e[34mhello\e[0m"
#   LLM::Paint["hello", :blue, :bold] # => "\e[34;1mhello\e[0m"
#   LLM::Paint["hello", :white, :on_red]
class LLM::Paint
  ##
  # @return [Hash<Symbol, Integer>]
  #  The codes that set the foreground color
  FOREGROUND = {
    black: 30, red: 31, green: 32, yellow: 33,
    blue: 34, magenta: 35, cyan: 36, white: 37
  }.freeze

  ##
  # @return [Hash<Symbol, Integer>]
  #  The codes that set the background color
  BACKGROUND = {
    on_black: 40, on_red: 41, on_green: 42, on_yellow: 43,
    on_blue: 44, on_magenta: 45, on_cyan: 46, on_white: 47
  }.freeze

  ##
  # @return [Hash<Symbol, Integer>]
  #  The codes that set an effect
  EFFECTS = {
    bold: 1, faint: 2, italic: 3, underline: 4,
    blink: 5, inverse: 7, hidden: 8, strikethrough: 9
  }.freeze

  ##
  # @return [String]
  #  The escape sequence that resets every attribute
  RESET = "\e[0m"

  ##
  # Wraps a string in the escape sequences that represent the
  # given colors and effects.
  # @param [String, #to_s] text
  #  The text to colorize
  # @param [Array<Symbol>] options
  #  A foreground color, a background color, and/or an effect
  # @raise [ArgumentError]
  #  When an option is neither a color nor an effect
  # @return [String]
  def self.[](text, *options)
    return text.to_s if options.empty? || !enabled?
    "\e[#{codes(options)}m#{text}#{RESET}"
  end

  ##
  # @return [Boolean]
  #  True when color is enabled
  def self.enabled?
    @enabled.nil? ? detect : @enabled
  end

  ##
  # Enables or disables color. When it is given nil it goes
  # back to detecting what the terminal supports.
  # @param [Boolean, nil] enabled
  # @return [void]
  def self.enabled=(enabled)
    @enabled = enabled.nil? ? nil : !!enabled
  end

  ##
  # Detects whether the terminal supports color. Color is
  # disabled when `$NO_COLOR` is set, and when standard output
  # is not a terminal.
  # @see https://no-color.org/
  # @return [Boolean]
  def self.detect
    return false unless ENV["NO_COLOR"].to_s.strip.empty?
    $stdout.tty?
  end

  ##
  # @api private
  # @param [Array<Symbol>] options
  # @return [String]
  def self.codes(options)
    options.map { |option| code(option) }.join(";")
  end

  ##
  # @api private
  # @param [Symbol] option
  # @raise [ArgumentError]
  # @return [Integer]
  def self.code(option)
    FOREGROUND[option] || BACKGROUND[option] || EFFECTS[option] ||
      raise(ArgumentError, "unknown color or effect: #{option.inspect}")
  end
  private_class_method :codes, :code
end
