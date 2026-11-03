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
  # The default intercept is
  # {LLM::Intercept::Null LLM::Intercept::Null}
  # and it is a noop.
  class Intercept
    ##
    # @param [Class] klass
    #  A subclass of {LLM::Intercept}
    # @return [void]
    def self.inherited(klass)
      klass.prepend Rescue
    end

    require_relative "intercept/rescue"
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
    #  The contents of `intercept_options:`
    # @return [LLM::Function::Return, Object]
    #  When this method returns a
    #  {LLM::Function::Return LLM::Function::Return},
    #  object it stops a tool call
    #  in its tracks and the Return
    #  object is the answer we give
    #  to the model for the tool call
    #  that was stopped. Any other return
    #  value lets the tool call through.
    def call(function:, **opts)
      raise NotImplementedError
    end

    ##
    # Returns the options the context passed to `intercept_options:`.
    # @return [Hash]
    def options
      @options || {}
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
