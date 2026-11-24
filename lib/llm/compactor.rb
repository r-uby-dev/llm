# frozen_string_literal: true

module LLM
  ##
  # {LLM::Compactor LLM::Compactor} is the superclass for context compaction
  # strategies in llm.rb.
  #
  # A compactor is bound to a context and decides whether and how to compact
  # the conversation history when {#call} is invoked. Each subclass
  # implements a different strategy: {LLM::Compactor::Auto} trims the
  # conversation when the context window fills and is the default,
  # {LLM::Compactor::Truncate} drops the oldest messages, and
  # {LLM::Compactor::Null} is a no-op.
  #
  # The compactor does not have a separate `compact?` predicate. It inspects
  # the context internally and returns `nil` when nothing needs to happen.
  # Callers invoke {#call} unconditionally.
  class Compactor
    require_relative "compactor/truncate"
    require_relative "compactor/null"
    require_relative "compactor/auto"

    ##
    # @return [LLM::Context]
    attr_reader :ctx

    ##
    # @param ctx [LLM::Context, LLM::Agent]
    # @return [LLM::Compactor]
    def initialize(ctx)
      @ctx = LLM::Agent === ctx ? ctx.instance_variable_get(:@ctx) : ctx
    end

    ##
    # @abstract
    # @param opts [Hash] Per-call options
    # @return [Object, nil]
    def call(**opts)
      raise NotImplementedError
    end

    private

    ##
    # @return [LLM::Stream]
    def stream
      @ctx.params[:stream]
    end

    ##
    # @return [LLM::Buffer]
    def messages
      @ctx.messages
    end
  end
end
