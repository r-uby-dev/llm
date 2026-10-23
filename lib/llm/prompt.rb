# frozen_string_literal: true

##
# {LLM::Prompt LLM::Prompt} is a small object for composing
# a single request from multiple role-aware messages.
# A prompt is not just a string. It is an ordered chain of
# messages with explicit roles (for example `system` and `user`).
# Use {LLM::Context#prompt} when building a prompt inside a session.
# Use `LLM::Prompt.new(provider)` directly when you want to construct
# or pass prompt objects around explicitly.
#
# @example
#   llm = LLM.openai(key: ENV["KEY"])
#   ctx = LLM::Context.new(llm)
#
#   prompt = ctx.prompt do
#     system "Your task is to assist the user"
#     user "Hello. Can you assist me?"
#   end
#
#   res = ctx.talk(prompt)
class LLM::Prompt
  ##
  # @param [LLM::Provider] llm
  #  A provider used to resolve provider-specific role names.
  # @param [Proc] b
  #  A block that composes messages. If the block takes one argument,
  #  it receives the prompt object. Otherwise the block runs in the
  #  prompt context via `instance_eval`.
  def initialize(llm, &b)
    @llm = llm
    @buffer = []
    unless b.nil?
      (b.arity == 1) ? b.call(self) : instance_eval(&b)
    end
  end

  ##
  # @param [String] content
  #  The message
  # @param [Symbol] role
  #  The role (eg user, system)
  # @param [Hash, nil] extra
  #  Fields carried alongside the message. A caller that composes a
  #  message of its own can mark it here, and the runtime reads the
  #  mark back rather than inferring it from the role.
  # @return [void]
  def talk(content, role: @llm.user_role, extra: nil)
    role = case role.to_sym
    when :system then @llm.system_role
    when :user then @llm.user_role
    when :developer then @llm.developer_role
    else role
    end
    message = extra ? LLM::Message.new(role, content, extra) : LLM::Message.new(role, content)
    @buffer << message
  end
  alias_method :chat, :talk

  ##
  # @param [String] content
  #  The message content
  # @param [Hash, nil] extra
  #  Fields carried alongside the message
  # @return [void]
  def user(content, extra: nil)
    talk(content, role: @llm.user_role, extra:)
  end

  ##
  # @param [String] content
  #  The message content
  # @param [Hash, nil] extra
  #  Fields carried alongside the message
  # @return [void]
  def system(content, extra: nil)
    talk(content, role: @llm.system_role, extra:)
  end

  ##
  # @param [String] content
  #  The message content
  # @param [Hash, nil] extra
  #  Fields carried alongside the message
  # @return [void]
  def developer(content, extra: nil)
    talk(content, role: @llm.developer_role, extra:)
  end

  ##
  # @return [Array<LLM::Message>]
  #  Returns the prompt messages in order.
  def to_a
    @buffer.dup
  end

  ##
  # Returns true when two prompts have the same buffer
  # @param [LLM::Prompt] other
  # @return [Boolean]
  def ==(other)
    return false unless LLM::Prompt === other
    @buffer == other.to_a
  end
  alias_method :eql?, :==
end
