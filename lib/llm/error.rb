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
  # When a request is interrupted.
  #
  # This is a signal rather than an error, so that a bare `rescue` cannot
  # swallow it: an interrupt is a request to stop, and a turn whose cancel
  # was eaten looks like a turn that ignored one. The signal it names is
  # `INT`, which is what an interrupt is, and the message it carries is the
  # one it was raised with rather than a signal name.
  class Interrupt < SignalException
    ##
    # @param [String, nil] message
    def initialize(message = nil)
      super("INT")
      @message = message
    end

    ##
    # @return [String]
    def message
      @message || super
    end
    alias_method :to_s, :message
  end

  ##
  # HTTPUnauthorized
  UnauthorizedError = Class.new(Error)

  ##
  # HTTPTooManyRequests
  RateLimitError = Class.new(Error)

  ##
  # A tokens-per-minute (TPM) rate limit. Alibaba reports this as
  # `Throttling.AllocationQuota` / `insufficient_quota`. It is a
  # rate limit (retriable), distinct from a request-rate limit only
  # for classification.
  InsufficientQuotaError = Class.new(RateLimitError)

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
