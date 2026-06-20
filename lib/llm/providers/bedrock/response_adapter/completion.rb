# frozen_string_literal: true

module LLM::Bedrock::ResponseAdapter
  ##
  # Adapts Bedrock Converse API completion responses.
  #
  # The Bedrock Converse response body looks like:
  #   {
  #     "output" => {"message" => {
  #       "role" => "assistant",
  #       "content" => `[ { "text" => "..." }, { "toolUse" => ... } ]`
  #     }},
  #     "usage" => `{ "inputTokens" => N, "outputTokens" => N }`,
  #     "modelId" => "anthropic.claude-sonnet-4-20250514-v1:0",
  #     "stopReason" => "end_turn"
  #   }
  module Completion
    ##
    # (see LLM::Contract::Completion#messages)
    def messages
      source = texts.empty? && tools.any? ? [{"text" => ""}] : texts
      source.map.with_index do |choice, index|
        extra = {
          index:, response: self,
          reasoning_content:,
          tool_calls: adapt_tool_calls(tools),
          original_tool_calls: tools
        }
        LLM::Message.new(role, choice["text"], extra)
      end
    end
    alias_method :choices, :messages

    ##
    # Returns the Bedrock request id when present.
    # @return [String, nil]
    def id
      res["x-amzn-requestid"] || res["x-amzn-request-id"]
    end

    ##
    # (see LLM::Contract::Completion#input_tokens)
    def input_tokens
      body.usage&.inputTokens || 0
    end

    ##
    # (see LLM::Contract::Completion#output_tokens)
    def output_tokens
      body.usage&.outputTokens || 0
    end

    ##
    # (see LLM::Contract::Completion#reasoning_tokens)
    def reasoning_tokens
      0
    end

    ##
    # (see LLM::Contract::Completion#input_audio_tokens)
    def input_audio_tokens
      super
    end

    ##
    # (see LLM::Contract::Completion#output_audio_tokens)
    def output_audio_tokens
      super
    end

    ##
    # (see LLM::Contract::Completion#input_image_tokens)
    def input_image_tokens
      super
    end

    ##
    # (see LLM::Contract::Completion#cache_read_tokens)
    def cache_read_tokens
      0
    end

    ##
    # (see LLM::Contract::Completion#cache_write_tokens)
    def cache_write_tokens
      0
    end

    ##
    # (see LLM::Contract::Completion#total_tokens)
    def total_tokens
      input_tokens + output_tokens
    end

    ##
    # (see LLM::Contract::Completion#usage)
    def usage
      super
    end

    ##
    # (see LLM::Contract::Completion#model)
    def model
      body.modelId
    end

    ##
    # (see LLM::Contract::Completion#content)
    def content
      super
    end

    ##
    # (see LLM::Contract::Completion#reasoning_content)
    def reasoning_content
      @reasoning_content ||= begin
        text = parts.filter_map { _1.dig("reasoningContent", "text") }.join
        text.empty? ? nil : text
      end
    end

    ##
    # (see LLM::Contract::Completion#content!)
    def content!
      super
    end

    private

    def adapt_tool_calls(tools)
      (tools || []).filter_map do |tool|
        next unless tool["toolUse"]
        {
          id: tool["toolUse"]["toolUseId"],
          name: tool["toolUse"]["name"],
          arguments: parse_tool_input(tool["toolUse"]["input"])
        }
      end
    end

    def parse_tool_input(input)
      case input
      when Hash then input
      when String
        parsed = LLM.json.load(input)
        Hash === parsed ? parsed : {}
      when nil then {}
      else input.respond_to?(:to_h) ? input.to_h : {}
      end
    rescue *LLM.json.parser_error
      {}
    end

    def parts
      raw = body.output&.message&.content || []
      raw.is_a?(Array) ? raw : [raw].compact
    end

    def texts
      @texts ||= parts.select { |b| b["text"] }
    end

    def tools
      @tools ||= parts.select { |b| b["toolUse"] }
    end

    def role
      body.output&.message&.role || "assistant"
    end

    include LLM::Contract::Completion
  end
end
