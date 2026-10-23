# frozen_string_literal: true

module LLM
  class Message
    ##
    # Returns the role of the message
    # @return [Symbol]
    attr_reader :role

    ##
    # Returns the content of the message
    # @return [String]
    attr_reader :content

    ##
    # Returns extra context associated with the message
    # @return [Hash]
    attr_reader :extra

    ##
    # Returns a stable id for this message. It is generated once
    # on creation and restored with the runtime state on load.
    # @return [String]
    attr_reader :id

    ##
    # Returns a new message
    # @param [Symbol] role
    # @param [String] content
    # @param [Hash] extra
    # @return [LLM::Message]
    def initialize(role, content, extra = {})
      @role = normalize_role(role, content)
      @content = content
      @extra = LLM::Object.from(extra)
      @id = extra[:id] || SecureRandom.uuid_v7
    end

    ##
    # Returns the time this message was created, derived from the
    # timestamp embedded in its UUIDv7 id, or nil when it is not.
    # @return [Time, nil]
    def created_at
      @created_at ||= LLM::Utils.timestamp(@id)
    end

    ##
    # Returns a Hash representation of the message.
    #
    # This is the whole of a message as far as storage is concerned:
    # {LLM::Context#to_h} maps its messages through here, and restore
    # reads them back from the same list. A field that is not named
    # here does not survive a save, so a field the runtime relies on
    # after a restore has to be named.
    # @return [Hash]
    def to_h
      {
        id: @id,
        role:,
        content:,
        reasoning_content:,
        compaction: extra.compaction,
        instructions: extra.instructions,
        tools: extra.tool_calls&.map { LLM::Object === _1 ? _1.to_h : _1 },
        usage:,
        original_tool_calls: extra.original_tool_calls
      }.compact.then { preserve_nil_content(_1) }
    end

    ##
    # @return [String]
    def to_json(...)
      LLM.json.dump(to_h, ...)
    end

    ##
    # Returns true when two objects have the same role and content.
    # The id is ignored, because it identifies a message rather than
    # describing it.
    # @param [Object] other
    #  The other object to compare
    # @return [Boolean]
    def ==(other)
      if other.respond_to?(:to_h)
        to_h.except(:id) == other.to_h.except(:id)
      else
        false
      end
    end
    alias_method :eql?, :==

    ##
    # Try to parse JSON content
    # @return [Hash]
    #  Returns the parsed content as a Hash
    def content!
      LLM.json.load(content)
    end

    ##
    # Returns reasoning content associated with the message
    # @return [String, nil]
    def reasoning_content
      extra.reasoning_content
    end

    ##
    # Returns true when a message was created by context compaction
    # @return [Boolean]
    def compaction?
      !!extra.compaction
    end

    ##
    # Returns true when a message contains an image URL
    # @return [Boolean]
    def image_url?
      image_urls.any?
    end

    ##
    # Returns image URL content items from the message
    # @return [Array<LLM::Object>]
    def image_urls
      content_items.select { LLM::Object === _1 && _1.kind == :image_url }
    end

    ##
    # Returns true when a message contains a local or remote file
    # @return [Boolean]
    def file?
      files.any?
    end

    ##
    # Returns local and remote file content items from the message
    # @return [Array<LLM::Object>]
    def files
      content_items.select do
        LLM::Object === _1 && [:local_file, :remote_file].include?(_1.kind)
      end
    end

    ##
    # @return [Array<LLM::Function>]
    def functions
      @functions ||= tool_calls.filter_map do |fn|
        function = available_tools.find { _1.name.to_s == fn.name } || function_missing(fn.name)
        function = function.dup
        function.tap { _1.id = fn.id }
        function.tap { _1.arguments = fn.arguments }
      end
    end

    ##
    # Returns true when the message is an assistant message
    # @return [Boolean]
    def assistant?
      role == "assistant" || role == "model"
    end

    ##
    # Returns true when the message is a system message
    # @return [Boolean]
    def system?
      role == "system"
    end

    ##
    # Returns true when the message is a user message
    # @return [Boolean]
    def user?
      role == "user"
    end

    ##
    # @return [Boolean]
    #  Returns true when the message requests a function call
    def tool_call?
      tool_calls.any?
    end

    ##
    # @return [Boolean]
    #  Returns true when the message represents a function return
    def tool_return?
      LLM::Function::Return === content ||
        [*content].grep(LLM::Function::Return).any?
    end

    ##
    # @note
    #  This method returns a response for assistant messages,
    #  and it returns nil for non-assistant messages
    # @return [LLM::Response, nil]
    #  Returns the response associated with the message, or nil
    def response
      extra.response
    end

    ##
    # @note
    #  This method might return annotations for assistant messages,
    #  and it returns an empty array for non-assistant messages
    # Returns annotations associated with the message
    # @return [Array<LLM::Object>]
    def annotations
      @annotations ||= LLM::Object.from(extra.annotations || [])
    end

    ##
    # @note
    #  This method returns token usage for assistant messages,
    #  and it returns nil for non-assistant messages
    # Returns token usage statistics
    # @return [LLM::Usage, nil]
    def token_usage
      return nil unless assistant?
      @token_usage ||= LLM::Usage.from(extra.usage || response&.usage)
    end
    alias_method :usage, :token_usage

    ##
    # @return [String, nil]
    #  Returns the model associated with a message
    def model
      response&.model
    end

    ##
    # Returns a string representation of the message
    # @return [String]
    def inspect
      "#<#{LLM::Utils.object_id(self)} " \
      "tool_call=#{tool_calls.any?} role=#{role.inspect} " \
      "content=#{content.inspect} reasoning_content=#{reasoning_content.inspect}>"
    end

    private

    ##
    # Normalizes a role to the abstract role the runtime
    # stores: `assistant` for a model reply, `tool` for a
    # tool return. The provider's spelling is produced
    # again at assembly time by
    # {LLM::RequestAdapter::Role#adapt_role}.
    #
    # Content is consulted as well as the role, because
    # an Anthropic or Bedrock tool return arrives under
    # `user`.
    # @param [Symbol, String] role
    # @param [Object] content
    # @return [String]
    def normalize_role(role, content)
      case role.to_s
      when "assistant", "model" then "assistant"
      when "tool" then "tool"
      else holds_tool_return?(content) ? "tool" : role.to_s
      end
    end

    ##
    # @param [Object] content
    # @return [Boolean]
    #  Returns true when content holds a tool return
    def holds_tool_return?(content)
      LLM::Function::Return === content || [*content].any? { LLM::Function::Return === it }
    end

    ##
    # @return [Hash]
    def preserve_nil_content(hash)
      hash[:content] = content if content.nil?
      hash
    end

    ##
    # @return [LLM::Object]
    def tool_calls
      @tool_calls ||= LLM::Object.from(extra.tool_calls || [])
    end

    ##
    # @return [Array<LLM::Function>]
    def available_tools
      tools = extra.tools || []
      tools = nil if tools.empty?
      tools = tools || response&.__tools__ || []
      tools.map { _1.respond_to?(:function) ? _1.function : _1 }
    end

    ##
    # @return [LLM::Function]
    def function_missing(name)
      LLM.function(name) do |fn|
        fn.define { raise LLM::NoSuchToolError, "tool '#{name}' not found" }
      end
    end

    ##
    # retrurn [Array]
    def content_items
      Array(content)
    end
  end
end
