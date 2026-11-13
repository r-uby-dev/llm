# frozen_string_literal: true

class LLM::Compactor
  ##
  # An {LLM::Compactor::Null LLM::Compactor::Null} is a compactor that
  # does nothing. It is the compactor to configure when a context should
  # never compact - {LLM::Compactor::Auto} is the default.
  #
  # All methods return nil and produce no side effects.
  class Null < self
    ##
    # @param [Hash] opts
    #  Ignored
    # @return [nil]
    def call(**opts)
      nil
    end
  end
end
