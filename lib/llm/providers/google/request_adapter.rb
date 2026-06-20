# frozen_string_literal: true

class LLM::Google
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
    # @param [Hash] params
    # @return [Hash]
    def adapt_schema(params)
      return {} unless params and params[:schema]
      schema = params.delete(:schema)
      schema = schema.respond_to?(:object) ? schema.object : schema
      {generationConfig: {response_mime_type: "application/json", response_schema: schema}}
    end

    ##
    # @param [Array<LLM::Function>] tools
    # @return [Hash]
    def adapt_tools(tools)
      return {} unless tools&.any?
      platform, functions = [tools.grep(LLM::ServerTool), tools.grep(LLM::Function)]
      {tools: [*platform, {functionDeclarations: functions.map { _1.adapt(self) }}]}
    end
  end
end
