# frozen_string_literal: true

module LLM
  ##
  # An intercept sits between the model and a tool call. It decides
  # whether the call runs, and what the call is: the
  # {LLM::Function LLM::Function} handed to {#call call} is the pending
  # call itself, so an intercept can rewrite its arguments in place and
  # let the call continue by returning `nil`.
  #
  # A call that should not run is closed by returning an instance of
  # {LLM::Function::Return LLM::Function::Return}: the tool never runs, and
  # the model is given that return as the call's result.
  #
  # {LLM::Intercept::Null LLM::Intercept::Null} is a no-op and the default.
  # {LLM::Guard LLM::Guard} is the name this class had before it was
  # renamed, and it is kept as an alias of it.
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

##
# {LLM::Guard LLM::Guard} is the name {LLM::Intercept LLM::Intercept} had
# before it was renamed. It is kept so that code written against it keeps
# working, and it is the same class rather than a copy of it.
LLM::Guard = LLM::Intercept
