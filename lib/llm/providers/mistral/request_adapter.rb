# frozen_string_literal: true

class LLM::Mistral
  ##
  # @private
  module RequestAdapter
    require_relative "request_adapter/completion"
    include LLM::OpenAI::RequestAdapter

    ##
    # @param [Array<LLM::Message>] messages
    #  The messages to adapt
    # @return [Array<Hash>]
    def adapt(messages, mode: nil)
      messages.filter_map do |message|
        Completion.new(self, message).adapt
      end
    end
  end
end
