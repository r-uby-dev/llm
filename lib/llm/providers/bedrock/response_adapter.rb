# frozen_string_literal: true

class LLM::Bedrock
  ##
  # Adapts Bedrock Converse API responses to llm.rb's Response format.
  #
  # Bedrock Converse returns:
  #   {
  #     output: `{ message: { role: "assistant", content: [ ... ] } }`,
  #     usage: `{ inputTokens: N, outputTokens: N }`,
  #     modelId: "anthropic.claude-...",
  #     stopReason: "end_turn" | "tool_use" | "max_tokens" | ...
  #   }
  #
  # @api private
  module ResponseAdapter
    module_function

    ##
    # @param [LLM::Response, Net::HTTPResponse] res
    # @param [Symbol] type
    # @return [LLM::Response]
    def adapt(res, type:)
      response = (LLM::Response === res) ? res : LLM::Response.new(res)
      response.extend(select(type))
    end

    ##
    # @api private
    def select(type)
      case type
      when :completion then LLM::Bedrock::ResponseAdapter::Completion
      when :models then LLM::Bedrock::ResponseAdapter::Models
      else
        raise ArgumentError,
              "Unknown response adapter type: #{type.inspect}"
      end
    end
  end
end
