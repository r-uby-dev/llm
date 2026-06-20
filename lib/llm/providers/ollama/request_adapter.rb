# frozen_string_literal: true

class LLM::Ollama
  ##
  # @private
  module RequestAdapter
    require_relative "request_adapter/completion"

    ##
    # @param [Array<LLM::Message>] messages
    #  The messages to adapt
    # @return [Array<Hash>]
    def adapt(messages, mode: nil)
      messages.filter_map do |message|
        Completion.new(message).adapt
      end
    end

    private

    ##
    # @param [Array<LLM::Function>] tools
    # @return [Hash]
    def adapt_tools(tools)
      return {} unless tools&.any?
      {tools: tools.map { _1.adapt(self) }}
    end
  end
end
