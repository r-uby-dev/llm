# frozen_string_literal: true

class LLM::Console
  ##
  # The {LLM::Console::Bar LLM::Console::Bar} class renders a
  # small progress bar for the REPL. It is used to show
  # the remaining size of the model's context window in
  # a compact form near the input line.
  # @api private
  class Bar
    ##
    # @return [String]
    OCCUPIED = "█"

    ##
    # @return [String]
    FREE = " "

    ##
    # @param [Rational, nil] fraction
    #  The fraction of the context window used, or nil when unknown
    #  (eg after compaction).
    # @param [Integer] width
    # @return [LLM::Console::Bar]
    def initialize(fraction:, width: 10)
      @width = width
      @label, @filled = remainder(fraction)
    end

    ##
    # @return [String]
    def to_s
      bar = "#{OCCUPIED * filled}#{FREE * (width - filled)}"
      "│#{bar}│ #{label}"
    end

    private

    ##
    # @param [Rational, nil] fraction
    # @return [[String, Integer]]
    def remainder(fraction)
      return ["???", width] if fraction.nil?
      remaining = (1 - fraction).to_f * 100
      remaining = 0.0 if remaining <= 0
      ["#{remaining.round(2)}%", ((remaining / 100) * width).round]
    end

    attr_reader :label, :filled, :width
  end
end
