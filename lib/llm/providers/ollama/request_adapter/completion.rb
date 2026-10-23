# frozen_string_literal: true

module LLM::Ollama::RequestAdapter
  ##
  # @private
  class Completion
    include LLM::RequestAdapter::Role

    ##
    # @param [LLM::Provider] llm
    # @param [LLM::Message] message
    #  The message to format
    def initialize(llm, message)
      @llm = llm
      @message = message
    end

    ##
    # Adapts the message for the Ollama chat completions API
    # @return [Hash]
    def adapt
      catch(:abort) do
        if Hash === message
          {role: adapt_message_role(message)}.merge(adapt_content(message[:content]))
        else
          adapt_message
        end
      end
    end

    private

    def adapt_content(content)
      case content
      when String
        {content:}
      when LLM::Message
        adapt_content(content.content)
      when LLM::Function::Return
        throw(:abort, adapt_return(content))
      when LLM::Object
        adapt_object(content)
      else
        prompt_error!(content)
      end
    end

    ##
    # @param [LLM::Function::Return] result
    # @return [Hash]
    def adapt_return(result)
      {role: adapt_role(:tool), tool_call_id: result.id, content: LLM.json.dump(result.value)}
    end

    def adapt_message
      case content
      when Array
        adapt_array
      else
        {role: adapt_message_role(message)}.merge(adapt_content(content))
      end
    end

    def adapt_array
      if content.empty?
        nil
      elsif returns.any?
        returns.map { adapt_return(_1) }
      else
        content.flat_map { {role: adapt_message_role(message)}.merge(adapt_content(_1)) }
      end
    end

    def adapt_object(object)
      case object.kind
      when :local_file then adapt_local_file(object.value)
      when :remote_file then prompt_error!(object)
      when :image_url then prompt_error!(object)
      else prompt_error!(object)
      end
    end

    def adapt_local_file(file)
      if file.image?
        {content: "This message has an image associated with it", images: [file.to_b64]}
      else
        raise LLM::PromptError, "The given local file (an instance of #{file.class}) " \
                                "is not an image, and therefore not supported by the " \
                                "Ollama API"
      end
    end

    def prompt_error!(object)
      if LLM::Object === object
        raise LLM::PromptError, "The given LLM::Object with kind '#{content.kind}' is not " \
                                "supported by the Ollama API"
      else
        raise LLM::PromptError, "The given object (an instance of #{object.class}) " \
                                "is not supported by the Ollama API"
      end
    end

    def message = @message
    def content = message.content
    def returns = content.grep(LLM::Function::Return)
  end
end
