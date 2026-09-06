# frozen_string_literal: true

class LLM::Console::Input
  ##
  # A single editable character of the input.
  class Char
    ##
    # @param [String] char
    # @return [LLM::Console::Input::Char]
    def initialize(char)
      @char = char
    end

    ##
    # Returns true when both strings returned
    # by the #to_s method are considered equal
    # by String#==.
    # @param [#to_s] other
    # @return [Boolean]
    def ==(other)
      to_s == other.to_s
    end
    alias_method :eql?, :==

    ##
    # Returns a hash consistent with {#eql?},
    # so equal chars behave as the same key in
    # a Hash or Set.
    # @return [Integer]
    def hash
      to_s.hash
    end

    ##
    # @return [Boolean]
    def empty?
      @char == ""
    end

    ##
    # @return [String]
    def to_s
      @char.dup
    end
  end
end
