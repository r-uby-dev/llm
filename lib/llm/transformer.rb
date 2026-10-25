# frozen_string_literal: true

module LLM
  ##
  # {LLM::Transformer LLM::Transformer} is the superclass for
  # message transformers in llm.rb.
  #
  # A transformer is bound to a context and rewrites a single
  # message before it is sent to the provider. Each subclass
  # implements a different transformation: it takes a message in
  # {#call} and returns a message. {LLM::Transformer::Null} is a
  # no-op (the default).
  #
  # A transformer may mutate the message in place or return a new
  # one. Either way, the returned message is what gets sent.
  class Transformer
    require_relative "transformer/multi"
    require_relative "transformer/null"
    require_relative "transformer/delete_backtrace"

    ##
    # @param [LLM::Provider] llm
    # @param [Array<LLM::Transformer>] transformers
    # @return [LLM::Transformer::Multi]
    def self.multi(llm, *transformers)
      transformers = [LLM::Transformer::DeleteBacktrace, *transformers].uniq
       Multi.new(*transformers.map { Class === it ? it.new(llm) : it })
    end

    ##
    # @return [LLM::Context]
    attr_reader :ctx

    ##
    # @param ctx [LLM::Context, LLM::Agent]
    # @return [LLM::Transformer]
    def initialize(ctx)
      @ctx = LLM::Agent === ctx ? ctx.instance_variable_get(:@ctx) : ctx
    end

    ##
    # @abstract
    # @param [LLM::Message] message
    #  The message to transform
    # @param [Hash] opts
    #  Per-call options
    # @return [LLM::Message]
    def call(message:, **opts)
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
