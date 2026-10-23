# frozen_string_literal: true

module LLM::Google::RequestAdapter
  ##
  # @private
  class Completion
    include LLM::RequestAdapter::Role
    include LLM::RequestAdapter::Tool

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
          {role: adapt_message_role(message), parts: adapt_tool_calls}
        else
          {role: adapt_message_role(message), parts: adapt_content(message.content)}
        end
      end
    end

    ##
    # @return [Array<Hash>]
    #  The tool calls a message carries, as parts
    #
    # @note
    #  Gemini replays a call with the `thoughtSignature`
    #  it was issued with, so it is carried alongside the
    #  call and put back here. Version 1 of the payload
    #  had no field for it and encoded it in the call's
    #  id instead, so that is read as well.
    def adapt_tool_calls
      tool_calls.filter_map do |call|
        next unless call[:name]
        part = {functionCall: {name: call[:name], args: tool_call_arguments(call)}}
        signature = call[:signature] || legacy_signature(call[:id])
        signature ? part.merge(thoughtSignature: signature) : part
      end
    end

    ##
    # @note
    #  This reads what a version 1 payload wrote, so that a
    #  conversation saved by version 1 still replays a call
    #  with the signature it was issued with.
    #
    # FIXME: remove in v19, when a version 1 payload is no
    # longer in circulation.
    # @param [String, nil] id
    # @return [String, nil]
    #  The signature a version 1 id carries
    def legacy_signature(id)
      id = id.to_s
      return nil unless id.start_with?("google_")
      return nil if id.start_with?("google_call_")
      id.delete_prefix("google_")
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
