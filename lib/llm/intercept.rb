# frozen_string_literal: true

module LLM
  ##
  # When a model requests a tool call the
  # runtime represents it as an {LLM::Function}
  # that an intercept can see before it is
  # called. An intercept can return its own
  # {LLM::Function::Return} object that acts
  # as the response to the tool call, or it
  # can return `nil` to let the tool call
  # execute as normal.
  #
  # An intercept can also see the parameters
  # a model has requested to send to a tool,
  # and it can modify them in-place before the
  # tool is called.
  #
  # The default intercept is {LLM::Intercept::Null LLM::Intercept::Null}
  # and it is a noop.
  class Intercept
    require_relative "intercept/null"
    require_relative "intercept/multi"

    ##
    # @param [LLM::Provider] llm
    #  An {LLM::Provider LLM::Provider}.
    # @param [Array<LLM::Intercept>] intercepts
    #  One or more subclasses of {LLM::Intercept LLM::Intercept}
    # @return [LLM::Intercept::Multi]
    def self.multi(llm, *intercepts)
      Multi.new(
        llm,
        *intercepts
      )
    end

    ##
    # @return [LLM::Provider]
    attr_reader :llm

    ##
    # @param [LLM::Provider] llm
    # @return [LLM::Intercept]
    def initialize(llm)
      @llm = llm
    end

    ##
    # @abstract
    # @param [LLM::Function] function
    #  A pending function
    # @param opts [Hash]
    #  The contents of 'guard_options:'
    # @return [LLM::Function::Return, nil]
    #  Returns a {LLM::Function::Return LLM::Function::Return},
    #  or nil. When nil is returned, the tool call continues,
    #  otherwise the Return object is the tool call's response
    def call(function:, **opts)
      raise NotImplementedError
    end

    private

    ##
    # @return [LLM::Context]
    def context
      @context
    end

    ##
    # @return [LLM::Stream]
    def stream
      context.params[:stream]
    end

    ##
    # @return [LLM::Buffer]
    def messages
      context.messages
    end
  end
end
