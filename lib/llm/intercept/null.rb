# frozen_string_literal: true

class LLM::Intercept
  ##
  # {LLM::Intercept::Null LLM::Intercept::Null} is a no-op intercept. It
  # never blocks pending tool work and is the default intercept used by
  # {LLM::Context LLM::Context}.
  class Null < self
    ##
    # @param (see LLM::Intercept#call)
    # @return (see LLM::Intercept#call)
    def call(function:, **opts)
      nil
    end
  end
end
