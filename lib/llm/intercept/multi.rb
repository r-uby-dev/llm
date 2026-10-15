# frozen_string_literal: true

class LLM::Intercept
  ##
  # The {LLM::Intercept::Multi LLM::Intercept::Multi}
  # class combines multiple intercepts into a single
  # intercept.
  #
  # The first intercept that returns an instance of
  # {LLM::Function::Return LLM::Function::Return}
  # stops all other intercepts from running, and when
  # an intercept returns `nil` the next one in the list
  # is called. When all intercepts return nil, the tool
  # is called.
  #
  # @see LLM::Intercept
  class Multi < self
    ##
    # @param [LLM::Provider] llm
    #  An {LLM::Provider LLM::Provider}.
    # @param [Array<LLM::Intercept>] intercepts
    #  One or more subclasses of {LLM::Intercept LLM::Intercept}.
    def initialize(llm, *intercepts)
      @llm = llm
      @intercepts = intercepts
    end

    ##
    # @param (see LLM::Intercept#call)
    # @return (see LLM::Intercept#call)
    def call(function:, **opts)
      @intercepts.each do |intercept|
        intercept = intercept.new(llm).tap { _1.instance_variable_set(:@context, context) }
        result = intercept.call(function:, **opts)
        return result if LLM::Function::Return === result
      end
      nil
    end
  end
end
