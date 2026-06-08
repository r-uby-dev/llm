# frozen_string_literal: true

module LLM
  ##
  # The superclass of all LLM errors
  class Error < RuntimeError
    ##
    # @return [LLM::Transport::Response, nil]
    #  Returns the response associated with an error, or nil
    attr_accessor :response

    def initialize(...)
      block_given? ? yield(self) : nil
      super
    end

    def message
      if response
        [super, response.body].join("\n")
      else
        super
      end
    end
  end

  ##
  # HTTPUnauthorized
  UnauthorizedError = Class.new(Error)

  ##
  # HTTPTooManyRequests
  RateLimitError = Class.new(Error)

  ##
  # HTTPServerError
  ServerError = Class.new(Error)

  ##
  # HTTPNotFound
  NotFoundError = Class.new(Error)

  ##
  # When an given an input object that is not understood
  FormatError = Class.new(Error)

  ##
  # When given a prompt object that is not understood
  PromptError = Class.new(FormatError)

  ##
  # When given an invalid request
  InvalidRequestError = Class.new(Error)

  ##
  # When the context window is exceeded
  ContextWindowError = Class.new(InvalidRequestError)

  ##
  # When stuck in a tool call loop
  ToolLoopError = Class.new(Error)

  ##
  # When a guard blocks pending tool execution
  GuardError = Class.new(Error)

  ##
  # When a request is interrupted
  Interrupt = Class.new(Error)

  ##
  # When a concurrency strategy cannot execute a given tool
  RactorError = Class.new(Error)

  ##
  # When a tool call cannot be mapped to a local tool
  NoSuchToolError = Class.new(Error)

  ##
  # When {LLM::Registry} can't map a model
  NoSuchModelError = Class.new(Error)

  ##
  # When {LLM::Registry} can't map a registry
  NoSuchRegistryError = Class.new(Error)

  ##
  # When an optional runtime dependency cannot be required
  LoadError = Class.new(Error)
end
