# frozen_string_literal: true

module LLM::OpenAI::ResponseAdapter
  module Completion
    ##
    # (see LLM::Contract::Completion#messages)
    def messages
      [*body.choices].map.with_index do |choice, index|
        message = choice.message
        extra = {
          index:, response: self,
          logprobs: choice.logprobs,
          reasoning_content: message.reasoning_content,
          tool_calls: adapt_tool_calls(message.tool_calls),
          original_tool_calls: message.tool_calls
        }
        LLM::Message.new(message.role, message.content, extra)
      end
    end
    alias_method :choices, :messages

    ##
    # (see LLM::Contract::Completion#input_tokens)
    def input_tokens
      body.usage&.prompt_tokens || 0
    end

    ##
    # (see LLM::Contract::Completion#output_tokens)
    def output_tokens
      body.usage&.completion_tokens || 0
    end

    ##
    # (see LLM::Contract::Completion#reasoning_tokens)
    def reasoning_tokens
      body
        .usage
        &.completion_tokens_details
        &.reasoning_tokens || 0
    end

    ##
    # (see LLM::Contract::Completion#input_audio_tokens)
    def input_audio_tokens
      body
        .usage
        &.prompt_tokens_details
        &.audio_tokens || 0
    end

    ##
    # (see LLM::Contract::Completion#output_audio_tokens)
    def output_audio_tokens
      body
        .usage
        &.completion_tokens_details
        &.audio_tokens || 0
    end

    ##
    # (see LLM::Contract::Completion#input_image_tokens)
    def input_image_tokens
      body
        .usage
        &.prompt_tokens_details
        &.image_tokens || 0
    end

    ##
    # (see LLM::Contract::Completion#cache_read_tokens)
    def cache_read_tokens
      body
        .usage
        &.prompt_tokens_details
        &.cached_tokens || 0
    end

    ##
    # (see LLM::Contract::Completion#cache_write_tokens)
    def cache_write_tokens
      0
    end

    ##
    # (see LLM::Contract::Completion#total_tokens)
    def total_tokens
      body.usage&.total_tokens || 0
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

    def adapt_tool_calls(tools)
      (tools || []).filter_map do |tool|
        next unless tool.function
        {id: tool.id, name: tool.function.name, arguments: parse_tool_arguments(tool.function.arguments)}
      end
    end

    def parse_tool_arguments(arguments)
      return {} if arguments.to_s.empty?
      parsed = LLM.json.load(arguments)
      Hash === parsed ? parsed : {}
    rescue *LLM.json.parser_error
      {}
    end

    include LLM::Contract::Completion
  end
end
