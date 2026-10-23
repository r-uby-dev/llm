# frozen_string_literal: true

module LLM::Google::ResponseAdapter
  module Completion
    ##
    # (see LLM::Contract::Completion#messages)
    def messages
      adapt_choices
    end
    alias_method :choices, :messages

    ##
    # (see LLM::Contract::Completion#id)
    def id
      body["responseId"]
    end

    ##
    # (see LLM::Contract::Completion#input_tokens)
    def input_tokens
      body.usageMetadata.promptTokenCount || 0
    end

    ##
    # (see LLM::Contract::Completion#output_tokens)
    def output_tokens
      body.usageMetadata.candidatesTokenCount || 0
    end

    ##
    # (see LLM::Contract::Completion#reasoning_tokens)
    def reasoning_tokens
      body.usageMetadata.thoughtsTokenCount || 0
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
      body.usageMetadata.totalTokenCount || 0
    end

    ##
    # (see LLM::Contract::Completion#usage)
    def usage
      super
    end

    ##
    # (see LLM::Contract::Completion#model)
    def model
      body.modelVersion
    end

    ##
    # (see LLM::Contract::Completion#content)
    def content
      super
    end

    ##
    # (see LLM::Contract::Completion#reasoning_content)
    def reasoning_content
      super
    end

    ##
    # (see LLM::Contract::Completion#content!)
    def content!
      super
    end

    private

    def adapt_choices
      candidates.map.with_index do |choice, cindex|
        content = choice.content || LLM::Object.new
        role = content.role || "model"
        parts = content.parts || [{"text" => choice.finishReason}]
        text = parts.filter_map { _1["text"] }.join
        extra = {
          index: cindex,
          response: self,
          tool_calls: adapt_tool_calls(parts, cindex)
        }
        LLM::Message.new(role, text, extra)
      end
    end

    def adapt_tool_calls(parts, cindex)
      (parts || []).each_with_index.filter_map do |part, pindex|
        tool = part["functionCall"]
        next unless tool
        call = {id: LLM::Google.tool_id(part:, cindex:, pindex:), name: tool.name, arguments: tool.args}
        (signature = part["thoughtSignature"]) ? call.merge(signature:) : call
      end
    end

    def candidates = body.candidates || []

    include LLM::Contract::Completion
  end
end
