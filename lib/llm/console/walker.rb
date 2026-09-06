# frozen_string_literal: true

class LLM::Console
  ##
  # Walks through an array from the last element backward,
  # one step at a time. {#next} moves forward toward the end.
  # Both methods clamp at the array boundaries.
  class Walker
    ##
    # Sets the cursor position
    attr_writer :cursor

    ##
    # @param [Array] items
    def initialize(items)
      @items = items
      @cursor = items.size
    end

    ##
    # @return [Object, String, nil]
    def next
      if @items.empty?
        nil
      elsif @cursor >= @items.size - 1
        @cursor = @items.size
        ""
      else
        @cursor += 1
        @items[@cursor]
      end
    end

    ##
    # @return [Object, nil]
    def prev
      if @items.empty?
        nil
      elsif @cursor <= 0
        @items[@cursor]
      else
        @cursor -= 1
        @items[@cursor]
      end
    end
  end
end
