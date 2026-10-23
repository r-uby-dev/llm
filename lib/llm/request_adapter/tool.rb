# frozen_string_literal: true

module LLM::RequestAdapter
  ##
  # Reads the abstract tool calls a message carries.
  #
  # A tool call is saved as `{id, name, arguments}` - the form
  # the runtime reasons about - and never in a provider's wire
  # form. Each adapter builds the block its provider expects
  # from that form, which is what lets a conversation saved
  # under one provider be restored under another.
  #
  # @see LLM::Message#to_h
  module Tool
    ##
    # @return [Array<LLM::Object>]
    #  The tool calls a message carries
    def tool_calls
      message.extra[:tool_calls].to_a
    end

    ##
    # @return [Array<Hash>]
    #  The tool calls a message carries, in the shape the
    #  OpenAI-compatible chat completions APIs share
    def adapt_tool_calls
      tool_calls.filter_map do |call|
        next unless call[:id] and call[:name]
        {
          id: call[:id],
          type: "function",
          function: {name: call[:name], arguments: tool_call_arguments_json(call)}
        }
      end
    end

    ##
    # @param [LLM::Object, Hash] call
    # @return [Hash]
    #  The parsed arguments of a tool call
    def tool_call_arguments(call)
      args = call[:arguments]
      case args
      when String then parse_tool_arguments(args)
      when nil then {}
      else args.respond_to?(:to_h) ? args.to_h : {}
      end
    end

    ##
    # @param [LLM::Object, Hash] call
    # @return [String]
    #  The arguments of a tool call, as JSON
    def tool_call_arguments_json(call)
      LLM.json.dump(tool_call_arguments(call))
    end

    private

    def parse_tool_arguments(arguments)
      parsed = LLM.json.load(arguments)
      Hash === parsed ? parsed : {}
    rescue *LLM.json.parser_error
      {}
    end
  end
end
