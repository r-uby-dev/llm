# frozen_string_literal: true

module LLM::Anthropic::RequestAdapter
  ##
  # @private
  class Completion
    include LLM::RequestAdapter::Role

    ##
    # @param [LLM::Provider] llm
    # @param [LLM::Message, Hash] message
    #  The message to format
    def initialize(llm, message)
      @llm = llm
      @message = message
    end

    ##
    # Adapts the message for the Anthropic chat completions API
    # @return [Hash]
    def adapt
      catch(:abort) do
        if Hash === message
          {role: adapt_message_role(message), content: adapt_content(message[:content])}
        else
          adapt_message
        end
      end
    end

    private

    def adapt_message
      if message.tool_call?
        {role: adapt_message_role(message), content: adapt_tool_calls}
      else
        {role: adapt_message_role(message), content: adapt_content(content)}
      end
    end

    def adapt_tool_calls
      message.extra[:tool_calls].filter_map do |tool|
        next unless tool[:id] && tool[:name]
        {type: "tool_use", id: tool[:id], name: tool[:name], input: LLM::Anthropic.parse_tool_input(tool[:arguments])}
      end
    end

    ##
    # @param [String, URI] content
    #  The content to format
    # @return [String, Hash]
    #  The formatted content
    def adapt_content(content)
      case content
      when Hash
        content.empty? ? throw(:abort, nil) : [content]
      when Array
        content.empty? ? throw(:abort, nil) : content.flat_map { adapt_content(_1) }
      when LLM::Object
        adapt_object(content)
      when String
        [{type: :text, text: content}]
      when LLM::Response
        adapt_remote_file(content)
      when LLM::Message
        adapt_content(content.content)
      when LLM::Function::Return
        [{type: "tool_result", tool_use_id: content.id, content: [{type: :text, text: LLM.json.dump(content.value)}]}]
      else
        prompt_error!(content)
      end
    end

    def adapt_object(object)
      case object.kind
      when :image_url
        [{type: :image, source: {type: "url", url: object.value.to_s}}]
      when :local_file
        adapt_local_file(object.value)
      when :remote_file
        adapt_remote_file(object.value)
      else
        prompt_error!(content)
      end
    end

    def adapt_local_file(file)
      if file.image?
        [{type: :image, source: {type: "base64", media_type: file.mime_type, data: file.to_b64}}]
      elsif file.pdf?
        [{type: :document, source: {type: "base64", media_type: file.mime_type, data: file.to_b64}}]
      else
        raise LLM::PromptError, "The given object (an instance of #{file.class}) " \
                                "is not an image or PDF, and therefore not supported by the " \
                                "Anthropic API"
      end
    end

    def adapt_remote_file(file)
      prompt_error!(file) unless file.file?
      [{type: file.file_type, source: {type: :file, file_id: file.id}}]
    end

    def prompt_error!(content)
      if LLM::Object === content
      else
        raise LLM::PromptError, "The given object (an instance of #{content.class}) " \
                                "is not supported by the Anthropic API."
      end
    end

    def message = @message
    def content = message.content
  end
end
