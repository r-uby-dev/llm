# frozen_string_literal: true

module LLM::Google::RequestAdapter
  ##
  # @private
  class Completion
    include LLM::RequestAdapter::Role

    ##
    # @param [LLM::Provider] llm
    # @param [LLM::Message, Hash] message
    def initialize(llm, message)
      @llm = llm
      @message = message
    end

    ##
    # Adapts the message for the Gemini chat completions API
    # @return [Hash]
    def adapt
      catch(:abort) do
        if Hash === message
          {role: adapt_message_role(message), parts: adapt_content(message[:content])}
        elsif message.tool_call?
          {role: adapt_message_role(message), parts: message.extra.original_tool_calls}
        else
          {role: adapt_message_role(message), parts: adapt_content(message.content)}
        end
      end
    end

    def adapt_content(content)
      case content
      when Array
        content.empty? ? throw(:abort, nil) : content.flat_map { adapt_content(_1) }
      when String
        [{text: content}]
      when LLM::Response
        adapt_remote_file(content)
      when LLM::Message
        adapt_content(content.content)
      when LLM::Function::Return
        [{functionResponse: {name: content.name, response: adapt_function_response(content.value)}}]
      when LLM::Object
        adapt_object(content)
      else
        prompt_error!(content)
      end
    end

    def adapt_object(object)
      case object.kind
      when :image_url
        [{file_data: {file_uri: object.value.to_s}}]
      when :local_file
        file = object.value
        [{inline_data: {mime_type: file.mime_type, data: file.to_b64}}]
      when :remote_file
        adapt_remote_file(object.value)
      else
        prompt_error!(object)
      end
    end

    def adapt_remote_file(file)
      return prompt_error!(file) unless file.file?
      [{file_data: {mime_type: file.mime_type, file_uri: file.uri}}]
    end

    def adapt_function_response(value)
      Hash === value ? value : {result: value}
    end

    def prompt_error!(object)
      if LLM::Object === object
        raise LLM::PromptError, "The given LLM::Object with kind '#{content.kind}' is not " \
                                "supported by the Gemini API"
      else
        raise LLM::PromptError, "The given object (an instance of #{object.class}) " \
                                "is not supported by the Gemini API"
      end
    end

    def message = @message
    def content = message.content
  end
end
