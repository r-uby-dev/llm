# frozen_string_literal: true

module LLM::OpenAI::ResponseAdapter
  module Responds
    ##
    # (see LLM::Contract::Completion#messages)
    def messages
      [adapt_message]
    end
    alias_method :choices, :messages

    ##
    # @return [String]
    def response_id
      respond_to?(:response) ? response["id"] : id
    end

    ##
    # @return [Array<Hash>]
    def annotations = messages[0].annotations

    ##
    # (see LLM::Contract::Completion#input_tokens)
    def input_tokens
      body.usage&.input_tokens || 0
    end
    alias_method :prompt_tokens, :input_tokens

    ##
    # (see LLM::Contract::Completion#output_tokens)
    def output_tokens
      body.usage&.output_tokens || 0
    end
    alias_method :completion_tokens, :output_tokens

    ##
    # (see LLM::Contract::Completion#reasoning_tokens)
    def reasoning_tokens
      body
        .usage
        &.output_tokens_details
        &.reasoning_tokens || 0
    end

    ##
    # (see LLM::Contract::Completion#input_audio_tokens)
    def input_audio_tokens
      body
        .usage
        &.input_tokens_details
        &.audio_tokens || 0
    end

    ##
    # (see LLM::Contract::Completion#output_audio_tokens)
    def output_audio_tokens
      body
        .usage
        &.output_tokens_details
        &.audio_tokens || 0
    end

    ##
    # (see LLM::Contract::Completion#input_image_tokens)
    def input_image_tokens
      super
    end

    ##
    # (see LLM::Contract::Completion#cache_read_tokens)
    def cache_read_tokens
      body
        .usage
        &.input_tokens_details
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
    # OpenAI's Responses API does not expose a system fingerprint.
    # @return [nil]
    def system_fingerprint
      nil
    end

    ##
    # Returns the aggregated text content from the response outputs.
    # @return [String]
    def output_text
      content
    end

    ##
    # (see LLM::Contract::Completion#content)
    def content
      super || ""
    end

    ##
    # (see LLM::Contract::Completion#content!)
    def content!
      super
    end

    ##
    # (see LLM::Contract::Completion#reasoning_content)
    def reasoning_content
      super
    end

    private

    def adapt_message
      message = LLM::Message.new(
        "assistant",
        +"",
        {response: self, tool_calls: [], reasoning_content: +""}
      )
      output.each do |choice|
        if choice.type == "function_call"
          message.extra[:tool_calls] << adapt_tool(choice)
        elsif choice.type == "reasoning"
          (choice.summary || []).each do |summary|
            next unless summary["type"] == "summary_text"
            message.extra["reasoning_content"] << summary["text"]
          end
        elsif choice.content
          choice.content.each do |c|
            next unless c["type"] == "output_text"
            message.content << c["text"] << "\n"
            next unless c["annotations"]
            message.extra["annotations"] = [*message.extra["annotations"], *c["annotations"]]
          end
        end
      end
      message
    end

    def adapt_tool(tool)
      {id: tool.call_id, name: tool.name, arguments: parse_tool_arguments(tool.arguments)}
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
