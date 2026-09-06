# frozen_string_literal: true

class LLM::Console::Input
  ##
  # Tracks the state of the active completion so that repeated
  # TAB presses can cycle through the candidate list.
  # @api private
  class Cache
    ##
    # @param [Array<String>] candidates
    # @param [Integer] index
    # @return [LLM::Console::Input::Cache]
    def initialize(candidates, index)
      @candidates = candidates
      @index = index
    end

    ##
    # @return [Array<String>]
    attr_reader :candidates

    ##
    # @return [Integer]
    attr_reader :index

    ##
    # Returns the next index, wrapping around the list.
    # @return [Integer]
    def next_index
      (@index + 1) % @candidates.size
    end

    ##
    # @return [String]
    def value
      @candidates[@index]
    end

    ##
    # @return [Boolean]
    def include?(str)
      @candidates.include?(str)
    end
  end
end
