# frozen_string_literal: true

class LLM::OpenAI
  ##
  # @private
  module RequestAdapter
    require_relative "request_adapter/completion"
    require_relative "request_adapter/respond"
    require_relative "request_adapter/moderation"

    ##
    # @param [Array<LLM::Message>] messages
    #  The messages to adapt
    # @param [Symbol] mode
    #  The mode to adapt the messages for
    # @return [Array<Hash>]
    def adapt(messages, mode: :complete)
      messages.filter_map do |message|
        if mode == :complete
          Completion.new(message).adapt
        else
          Respond.new(message).adapt
        end
      end
    end

    private

    ##
    # @param [Hash] params
    # @return [Hash]
    def adapt_schema(params)
      return {} unless params and params[:schema]
      schema = params.delete(:schema)
      schema = schema.respond_to?(:object) ? schema.object : schema
      {
        response_format: {
          type: "json_schema",
          json_schema: {name: "JSONSchema", schema:}
        }
      }
    end

    ##
    # @param [Array<LLM::Function>] tools
    # @return [Hash]
    def adapt_tools(tools)
      if tools.nil? || tools.empty?
        {}
      else
        {tools: tools.map { _1.respond_to?(:adapt) ? _1.adapt(self) : _1 }}
      end
    end
  end
end
