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
    def adapt_generation_config(params)
      return {} unless params
      config = {}
      if params[:schema]
        schema = params.delete(:schema)
        schema = schema.respond_to?(:object) ? schema.object : schema
        config.merge!(response_mime_type: "application/json", response_schema: schema)
      end
      params_map.each { config[_1] = params.delete(_2) if params.key?(_2) }
      config.merge!(params)
      config.empty? ? {} : {generationConfig: config}
    end

    ##
    # @param [Array<LLM::Function>] tools
    # @return [Hash]
    def adapt_tools(tools)
      return {} unless tools&.any?
      platform, functions = [tools.grep(LLM::ServerTool), tools.grep(LLM::Function)]
      {tools: [*platform, {functionDeclarations: functions.map { _1.adapt(self) }}]}
    end

    ##
    # @return [Hash]
    def params_map
      {
        topP: :top_p,
        topK: :top_k,
        maxOutputTokens: :max_tokens,
        stopSequences: :stop
      }
    end
  end
end
