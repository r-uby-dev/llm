# frozen_string_literal: true

class LLM::Intercept
  ##
  # The {LLM::Intercept::Null LLM::Intercept::Null} class
  # is the default intercept, and it does nothing but allow
  # the tool call through.
  #
  # @see LLM::Intercept
  class Null < self
    ##
    # @param (see LLM::Intercept#call)
    # @return (see LLM::Intercept#call)
    def call(function:, **opts)
      nil
    end
  end
end
