# frozen_string_literal: true

class LLM::Context
  ##
  # @api private
  module Deserializer
    ##
    # Restore a saved context state.
    #
    # The `context_used` and `context_window` keys carried by a payload
    # are projections for queryability. They are deliberately ignored
    # here: the runtime derives both from the messages and the
    # registry, so a payload can never seed them.
    #
    # The payload has to have been written by this version, which
    # {LLM::Context.validate_schema!} asserts: the payload is not
    # backwards compatible, so a payload from any other version -
    # older, newer, or carrying no version at all - is refused
    # rather than read on a best-effort basis.
    # @param [String, nil] path
    #  The path to a JSON file
    # @param [String, nil] string
    #  A raw JSON string
    # @param [Hash, nil] data
    #  A parsed context payload
    # @raise [LLM::Error]
    #  When the payload was written by another version
    # @raise [SystemCallError]
    #  Might raise a number of SystemCallError subclasses
    # @return [LLM::Context]
    def deserialize(path: nil, string: nil, data: nil)
      ctx = if data
        data
      elsif path.nil? and string.nil?
        raise ArgumentError, "a path, string, or data payload is required"
      elsif path
        LLM.json.load(::File.binread(path))
      else
        LLM.json.load(string)
      end
      LLM::Context.validate_schema!(version: ctx["schema_version"])
      @id = ctx["id"] || @id
      @created_at = nil
      @messages.concat [*ctx["messages"]].map { deserialize_message(_1) }
      @compacted = !!ctx["compacted"]
      self
    end
    alias_method :restore, :deserialize

    private

    ##
    # Rebuilds one message from a payload.
    #
    # The fields that describe a message are named here rather than
    # taken from everything the payload holds, so a field that
    # {LLM::Message#to_h} writes has to be read here as well - and one
    # that is not named is dropped on the way in, whatever the payload
    # carries. `instructions` marks the message an agent injected as its
    # own, and the agent looks for that mark rather than for a role or a
    # position when it refreshes the instructions in a restored
    # conversation.
    # @param [Hash] payload
    # @return [LLM::Message]
    def deserialize_message(payload)
      tool_calls = deserialize_tool_calls(payload["tools"])
      returns = deserialize_returns(payload["content"]) if returns.nil?
      usage = payload["usage"]
      reasoning_content = payload["reasoning_content"]
      compaction = payload["compaction"]
      instructions = payload["instructions"]
      id = payload["id"]
      extra = {
        tool_calls:,
        tools: @params[:tools],
        usage:,
        reasoning_content:,
        compaction:,
        instructions:,
        id:
      }.compact
      content = returns.nil? ? deserialize_content(payload["content"]) : returns
      LLM::Message.new(payload["role"], content, extra)
    end

    def deserialize_content(content)
      case content
      when Array
        content.map { deserialize_content(_1) }
      when Hash
        deserialize_object(content)
      else
        content
      end
    end

    def deserialize_object(object)
      case object["__llm_kind__"]
      when "image_url"
        LLM::Object.from(value: object["value"], kind: :image_url)
      when "local_file"
        LLM::Object.from(value: LLM.File(object["path"]), kind: :local_file)
      when "remote_file"
        LLM::Object.from(value: LLM::Object.from(object["value"] || {}), kind: :remote_file)
      else
        object
      end
    end

    def deserialize_tool_calls(items)
      items ||= []
      items.empty? ? nil : items
    end

    def deserialize_returns(items)
      returns = [*items].filter_map do |item|
        next unless Hash === item
        id, name, value = item.values_at("id", "name", "value")
        next if name.nil? || value.nil?
        LLM::Function::Return.new(id, name, value)
      end
      returns.empty? ? nil : returns
    end
  end
end
