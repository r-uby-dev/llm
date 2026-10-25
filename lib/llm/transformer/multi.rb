# frozen_string_literal: true

class LLM::Transformer
  ##
  # A transformer that fans out to multiple
  # other transformers, so a message can be
  # transformed multiple times by different
  # transformers.
  # @example
  #   transformer = LLM::Transformer.multi(
  #     llm,
  #     TransformerOne,
  #     TransformerTwo
  #   )
  class Multi < self
    ##
    # Returns the transformers under the
    # supervision of Multi
    # @return [Array<LLM::Transformer>]
    attr_reader :transformers

    ##
    # @param [Array<LLM::Tracer>] transformers
    #  The transformers to fan out to.
    #  A Multi has no provider of its own.
    def initialize(*transformers)
      super(nil)
      @transformers = transformers
    end

    ##
    # @param (see LLM::Transformer#call)
    # @return (see LLM::Transformer#call)
    def call(message:, **opts)
      @transformers.map do
        message = it.call(message:, **opts)
      end.last
    end
  end
end
