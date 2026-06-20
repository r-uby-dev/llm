# frozen_string_literal: true

class LLM::Bedrock
  ##
  # Adapts llm.rb internal message format to Bedrock Converse API format.
  #
  # Bedrock Converse uses:
  #   - system: `[ { text: "..." } ]`  (top-level, separate from messages)
  #   - messages: `[ { role: "user"|"assistant", content: [ ... ] } ]`
  #   - Content blocks: text, image, document, toolUse, toolResult
  #   - toolConfig: `{ tools: [ { toolSpec: { name:, description:, inputSchema: { json: ... } } } ] }`
  #
  # @api private
  module RequestAdapter
    ##
    # @param [Array<LLM::Message>] messages
    # @return [Hash]
    def adapt(messages, mode: nil)
      payload = {messages: [], system: []}
      messages.each do |message|
        adapted = Completion.new(message).adapt
        next if adapted.nil?
        if system?(message)
          payload[:system].concat Array(adapted[:content])
        else
          payload[:messages] << adapted
        end
      end
      payload.delete(:system) if payload[:system].empty?
      payload
    end

    private

    ##
    # @param [Hash] params
    # @return [Hash]
    def adapt_schema(params)
      return {} unless params&.key?(:schema)
      schema = params.delete(:schema)
      schema = schema.respond_to?(:object) ? schema.object : schema
      cleaned = schema.respond_to?(:to_h) ? schema.to_h : schema
      [:strict, "strict", :$schema, "$schema"].each { cleaned.delete(_1) }
      {
        outputConfig: {
          textFormat: {
            type: "json_schema",
            structure: {
              jsonSchema: {
                name: "response",
                schema: LLM.json.dump(cleaned)
              }
            }
          }
        }
      }
    end

    ##
    # @param [Array<LLM::Function>] tools
    # @return [Hash]
    def adapt_tools(tools)
      return {} unless tools&.any?
      {toolConfig: {tools: tools.map { |t| adapt_tool(t) }}}
    end

    ##
    # @param [LLM::Function] tool
    # @return [Hash]
    def adapt_tool(tool)
      function = tool.respond_to?(:function) ? tool.function : tool
      {
        toolSpec: {
          name: function.name,
          description: function.description,
          inputSchema: {
            json: function.params || default_input_schema
          }
        }
      }
    end

    def default_input_schema
      {"type" => "object", "properties" => {}, "required" => []}
    end

    def system?(message)
      if message.respond_to?(:system?)
        message.system?
      else
        Hash === message && message[:role].to_s == "system"
      end
    end
  end
end
