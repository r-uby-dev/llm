# frozen_string_literal: true

module LLM::Bedrock::RequestAdapter
  ##
  # Adapts a single message to Bedrock Converse content blocks.
  #
  # Bedrock Converse content blocks include:
  #   - { text: "..." }
  #   - { image: { format: "png", source: { bytes: "..." } } }
  #   - { document: { format: "pdf", name: "...", source: { bytes: "..." } } }
  #   - { toolUse: { toolUseId: "...", name: "...", input: ... } }
  #   - {toolResult: {toolUseId: "...", content: [{ text: "..." }]}}
  #
  # @api private
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
    # Adapts the message for the Bedrock Converse API
    # @return [Hash, nil]
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
        blocks = [*adapt_tool_calls]
        blocks.unshift(*adapt_content(content)) unless String === content && content.empty?
        {role: adapt_message_role(message), content: blocks}
      else
        {role: adapt_message_role(message), content: adapt_content(content)}
      end
    end

    ##
    # @return [Array<Hash>]
    #  The tool calls a message carries, as toolUse blocks
    def adapt_tool_calls
      tool_calls.filter_map do |call|
        next unless call[:id] and call[:name]
        {
          toolUse: {
            toolUseId: call[:id],
            name: call[:name],
            input: tool_call_arguments(call)
          }
        }
      end
    end

    ##
    # @param [String, Array, LLM::Object, LLM::Function::Return] content
    # @return [Array<Hash>, nil]
    def adapt_content(content)
      case content
      when Hash
        content.empty? ? throw(:abort, nil) : [content]
      when Array
        content.empty? ? throw(:abort, nil) : content.flat_map { adapt_content(_1) }
      when LLM::Object
        adapt_object(content)
      when String
        [{text: content}]
      when LLM::Response
        adapt_remote_file(content)
      when LLM::Message
        adapt_content(content.content)
      when LLM::Function::Return
        [{toolResult: {toolUseId: content.id, content: [{text: LLM.json.dump(content.value)}]}}]
      else
        prompt_error!(content)
      end
    end

    def adapt_object(object)
      case object.kind
      when :image_url
        [{image: {format: detect_format(object.value.to_s),
                  source: {url: object.value.to_s}}}]
      when :local_file
        adapt_local_file(object.value)
      when :remote_file
        adapt_remote_file(object.value)
      else
        prompt_error!(object)
      end
    end

    def adapt_local_file(file)
      if file.image?
        [{image: {format: file.format,
                  source: {bytes: file.to_b64}}}]
      elsif file.pdf?
        name = sanitize_name(file.basename)
        [{document: {format: "pdf", name:,
                     source: {bytes: file.to_b64}}}]
      else
        raise LLM::PromptError,
              "The #{file.class} is not an image or PDF, " \
              "and not supported by the Bedrock API"
      end
    end

    def adapt_remote_file(file)
      prompt_error!(file) unless file.file?
      [{file.file_type => {source: {file_id: file.id}}}]
    end

    def detect_format(url)
      case url
      when /\.png/i then "png"
      when /\.jpe?g/i then "jpeg"
      when /\.gif/i then "gif"
      when /\.webp/i then "webp"
      else "png"
      end
    end

    def sanitize_name(name)
      name.to_s.gsub(/[^a-zA-Z0-9_-]/, "_")
    end

    def prompt_error!(content)
      raise LLM::PromptError,
            "#{content.class} is not supported by the Bedrock API"
    end

    def message = @message
    def content = message.content
  end
end
