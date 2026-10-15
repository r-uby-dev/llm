# frozen_string_literal: true

module LLM
  ##
  # A guard decides if a tool
  # call should run or not. A guard
  # can answer on a tool's behalf
  # by returning an instance of
  # {LLM::Function::Return LLM::Function::Return}.
  # When a Return is returned the
  # tool call never runs but the
  # model still gets a response,
  # and when `nil` is returned
  # the tool call is scheduled to
  # run.
  #
  # A guard can also mutate the
  # {LLM::Function LLM::Function}
  # given to its `call` method so
  # it can mutate tool parameters in-place,
  # and let the tool call continue
  # by returning `nil`.
  class Guard
    require_relative "guard/null"
    require_relative "guard/multi"

    ##
    # @param [LLM::Agent,LLM::Context] ctx
    #  An agent, or its context.
    # @param [Array<LLM::Guard>]
    #  One or more subclasses of {LLM::Guard LLM::Guard}
    def self.multi(llm, *guards)
      Multi.new(
        llm,
        *guards
      )
    end

    ##
    # @return [LLM::Provider]
    attr_reader :llm

    ##
    # @param [LLM::Provider] llm
    # @return [LLM::Guard]
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
