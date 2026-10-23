# frozen_string_literal: true

module LLM::OpenAI::RequestAdapter
  ##
  # @private
  class Respond
    include LLM::RequestAdapter::Role
    include LLM::RequestAdapter::Tool

    ##
    # @param [LLM::Provider] llm
    # @param [LLM::Message] message
    #  The message to format
    def initialize(llm, message)
      @llm = llm
      @message = message
    end

    def adapt
      catch(:abort) do
        if Hash === message
          {role: adapt_message_role(message), content: adapt_content(message[:content])}
        elsif message.tool_call?
          adapt_tool_calls
        else
          adapt_message
        end
      end
    end

    private

    ##
    # @return [Array<Hash>]
    #  The tool calls a message carries, in Responses form
    def adapt_tool_calls
      tool_calls.filter_map do |call|
        next unless call[:id] and call[:name]
        {
          type: "function_call",
          call_id: call[:id],
          name: call[:name],
          arguments: tool_call_arguments_json(call)
        }
      end
    end

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
        {role: adapt_message_role(message), content: adapt_content(content, role: message.role)}
      end
    end

    def adapt_array
      if content.empty?
        nil
      elsif returns.any?
        adapt_returns(returns)
      else
        {role: adapt_message_role(message), content: content.flat_map { adapt_content(_1, role: message.role) }}
      end
    end

    def adapt_returns(returns)
      returns.map { {type: "function_call_output", call_id: _1.id, output: LLM.json.dump(_1.value)} }
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
      adapt_role(role) == "assistant" ? :output_text : :input_text
    end
  end
end
