# frozen_string_literal: true

module LLM::OpenAI::RequestAdapter
  ##
  # @private
  class Respond
    ##
    # @param [LLM::Message] message
    #  The message to format
    def initialize(message)
      @message = message
    end

    def adapt
      catch(:abort) do
        if Hash === message
          {role: message[:role], content: adapt_content(message[:content])}
        elsif message.tool_call?
          adapt_tool_calls(message.extra[:original_tool_calls])
        else
          adapt_message
        end
      end
    end

    private

    def adapt_content(content, role: message.role)
      case content
      when String
        [{type: text_content_type(role), text: content.to_s}]
      when LLM::Response then adapt_remote_file(content)
      when LLM::Message then adapt_content(content.content, role: content.role)
      when LLM::Object
        case content.kind
        when :image_url then [{type: :input_image, image_url: content.value.to_s}]
        when :remote_file then adapt_remote_file(content.value)
        when :local_file then adapt_local_file(content.value)
        else prompt_error!(content)
        end
      when Array then content.flat_map { adapt_content(_1, role:) }
      else
        prompt_error!(content)
      end
    end

    def adapt_message
      case content
      when LLM::Function::Return
        adapt_returns([content])
      when Array
        adapt_array
      else
        {role: message.role, content: adapt_content(content, role: message.role)}
      end
    end

    def adapt_array
      if content.empty?
        nil
      elsif returns.any?
        adapt_returns(returns)
      else
        {role: message.role, content: content.flat_map { adapt_content(_1, role: message.role) }}
      end
    end

    def adapt_returns(returns)
      returns.map { {type: "function_call_output", call_id: _1.id, output: LLM.json.dump(_1.value)} }
    end

    def adapt_tool_calls(tools)
      [*tools].map do |tool|
        h = LLM::Object.from(tool.to_h)
        # Backward compatibility for conversations that
        # started under the chat completions API and are
        # later continued through Responses.
        if h.type.to_s == "function"
          {
            type: "function_call",
            call_id: h.id,
            name: h.function.name,
            arguments: h.function.arguments || "{}"
          }
        else
          tool
        end
      end
    end

    def adapt_remote_file(content)
      prompt_error!(content) unless content.file?
      file = LLM::File(content.filename)
      if file.image?
        [{type: :input_image, file_id: content.id}]
      else
        [{type: :input_file, file_id: content.id}]
      end
    end

    def adapt_local_file(file)
      if file.image?
        [{type: :input_image, image_url: file.to_data_uri}]
      else
        [{type: :input_file, filename: file.basename, file_data: file.to_data_uri}]
      end
    end

    def prompt_error!(content)
      if LLM::Object === content
        raise LLM::PromptError, "The given LLM::Object with kind '#{content.kind}' is not " \
                                "supported by the OpenAI responses API."
      else
        raise LLM::PromptError, "The given object (an instance of #{content.class}) " \
                                "is not supported by the OpenAI responses API"
      end
    end

    def message = @message
    def content = message.content
    def returns = content.grep(LLM::Function::Return)

    def text_content_type(role)
      role.to_s == "assistant" ? :output_text : :input_text
    end
  end
end
