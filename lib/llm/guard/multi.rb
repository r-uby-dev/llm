# frozen_string_literal: true

class LLM::Guard
  ##
  # The {LLM::Guard::Multi LLM::Guard::Multi} class lets
  # you combine multiple guards into a single guard. The
  # first guard that returns an instance of
  # {LLM::Function::Return LLM::Function::Return}
  # stops all other guards from running, and when
  # guard returns `nil` the next guard in the chain
  # is called.
  class Multi < self
    ##
    # @param [LLM::Provider] llm
    #  An {LLM::Provider LLM::Provider}.
    # @param [Array<LLM::Guard>] guards
    #  One or more subclasses of {LLM::Guard LLM::Guard}.
    def initialize(llm, *guards)
      @llm = llm
      @guards = guards
    end

    ##
    # @param (see LLM::Guard#call)
    # @return (see LLM::Guard#call)
    def call(function:, **opts)
      @guards.each do |guard|
        guard  = guard.new(llm).tap { _1.instance_variable_set(:@context, context) }
        result = guard.call(function:, **opts)
        return result if LLM::Function::Return === result
      end
      nil
    end
  end
end
