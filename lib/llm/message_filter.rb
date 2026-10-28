# frozen_string_literal: true

module LLM
  ##
  # {LLM::MessageFilter LLM::MessageFilter} is the superclass for
  # message filters in llm.rb.
  #
  # A filter is bound to a context and rewrites a single
  # message before it is sent to the provider. Each subclass
  # implements a different rewrite: it takes a message in
  # {#call} and returns a message. {LLM::MessageFilter::Null} is a
  # no-op (the default).
  #
  # A filter may mutate the message in place or return a new
  # one. Either way, the returned message is what gets sent.
  class MessageFilter
    require_relative "message_filter/rescue"
    require_relative "message_filter/multi"
    require_relative "message_filter/null"
    require_relative "message_filter/delete_backtrace"

    ##
    # @param [Class] klass
    #  A subclalss of {LLM::Tracer}
    # @return [void]
    def self.inherited(klass)
      klass.prepend Rescue
    end

    ##
    # @param [LLM::Provider] llm
    # @param [Array<LLM::MessageFilter>] filters
    # @return [LLM::MessageFilter::Multi]
    def self.multi(llm, *filters)
      filters = [LLM::MessageFilter::DeleteBacktrace, *filters].uniq
      Multi.new(*filters.map { Class === it ? it.new(llm) : it })
    end

    ##
    # @return [LLM::Context]
    attr_reader :ctx

    ##
    # @param ctx [LLM::Context, LLM::Agent]
    # @return [LLM::MessageFilter]
    def initialize(ctx)
      @ctx = LLM::Agent === ctx ? ctx.instance_variable_get(:@ctx) : ctx
    end

    ##
    # @abstract
    # @param [LLM::Message] message
    #  The message to filter
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
