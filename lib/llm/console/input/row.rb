# frozen_string_literal: true

class LLM::Console::Input
  ##
  # One line of the input. `chars` holds the editable characters.
  # `break_type` records how this line got started: an auto-wrap
  # (`:space`) or a real newline (`:newline`). The first row has no
  # break type. It decides how the input is flattened on {Input#take}.
  class Row
    ##
    # @return [Array<Input::Char>]
    attr_reader :chars

    ##
    # @return [Symbol, nil]
    #  `:space` or `:newline`, or nil for the first row.
    attr_accessor :break_type

    ##
    # @param [Symbol, nil] break_type
    #  How this line was started.
    def initialize(break_type = nil)
      @chars = []
      @break_type = break_type
    end

    ##
    # @return [String]
    def to_s
      chars.map(&:to_s).join
    end

    ##
    # @return [Boolean]
    def empty?
      chars.empty?
    end
  end
end
