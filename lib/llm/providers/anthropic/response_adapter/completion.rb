# frozen_string_literal: true

module LLM::Anthropic::ResponseAdapter
  module Completion
    ##
    # (see LLM::Contract::Completion#messages)
    def messages
      adapt_choices
    end
    alias_method :choices, :messages

    ##
    # (see LLM::Contract::Completion#input_tokens)
    def input_tokens
      body.usage&.input_tokens || 0
    end

    ##
    # (see LLM::Contract::Completion#output_tokens)
    def output_tokens
      body.usage&.output_tokens || 0
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
      body.usage&.cache_read_input_tokens || 0
    end

    ##
    # (see LLM::Contract::Completion#cache_write_tokens)
    def cache_write_tokens
      body.usage&.cache_creation_input_tokens || 0
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
      body.model
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
      source = texts.empty? && tools.any? ? [{"text" => ""}] : texts
      source.map.with_index do |choice, index|
        extra = {
          index:, response: self,
          tool_calls: adapt_tool_calls(tools)
        }
        LLM::Message.new(role, choice["text"], extra)
      end
    end

    def adapt_tool_calls(tools)
      (tools || []).filter_map do |tool|
        {
          id: tool.id,
          name: tool.name,
          arguments: LLM::Anthropic.parse_tool_input(tool.input)
        }
      end
    end

    def parts = body.content
    def texts = @texts ||= parts.select { _1["type"] == "text" }
    def tools = @tools ||= parts.select { _1["type"] == "tool_use" }

    include LLM::Contract::Completion
  end
end
