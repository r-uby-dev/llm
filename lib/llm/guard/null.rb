# frozen_string_literal: true

class LLM::Guard
  ##
  # {LLM::Guard::Null LLM::Guard::Null} is a no-op guard. It never blocks
  # pending tool work and is the default guard used by
  # {LLM::Context LLM::Context}.
  class Null < self
    ##
    # @param (see LLM::Guard#call)
    # @return (see LLM::Guard#call)
    def call(function:, **opts)
      nil
    end
  end
end
