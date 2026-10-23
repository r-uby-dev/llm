# frozen_string_literal: true

module LLM::RequestAdapter
  ##
  # Maps a saved role to the role a provider expects.
  #
  # Messages are saved with an abstract role: `assistant`
  # for a model reply, `tool` for a tool return. The
  # provider's spelling is produced here, at assembly
  # time, and is never stored. Google writes `model`,
  # Anthropic wants tool returns under `user`.
  #
  # @see LLM::Provider#assistant_role
  # @see LLM::Provider#tool_role
  module Role
    ##
    # @param [Symbol, String] role
    #  An abstract role
    # @return [String]
    #  The role the provider expects
    def adapt_role(role)
      role = case role.to_s
      when "assistant", "model" then llm.assistant_role
      when "tool" then llm.tool_role
      when "system" then llm.system_role
      when "developer" then llm.developer_role
      when "user" then llm.user_role
      else role
      end
      role.to_s
    end

    ##
    # @param [LLM::Message, Hash] message
    # @return [String]
    #  The role a message is sent under
    def adapt_message_role(message)
      ##
      # A Hash isn't something the runtime saves,
      # so it carries no abstract role to map.
      return message[:role].to_s if Hash === message
      adapt_role(message.role)
    end

    private

    ##
    # @return [LLM::Provider]
    def llm
      @llm
    end
  end
end
