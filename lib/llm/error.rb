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
  # When a request is interrupted.
  #
  # It sits outside `StandardError`, so that neither a bare `rescue` nor a
  # `rescue => e` can swallow it by mistake: an interrupt is a request to
  # stop, and a turn whose cancel was eaten looks like a turn that ignored
  # one.
  #
  # It is not a `SignalException` either. A signal is a framework's own
  # condition rather than a task's - RSpec re-raises one that escapes an
  # example, and an async reactor ends its own thread rather than failing
  # the task that raised it - and an interrupt has to be something a caller
  # can catch.
  Interrupt = Class.new(Exception)

  ##
  # When a concurrency strategy cannot execute a given tool
  RactorError = Class.new(Error)

  ##
  # When a fiber tool's scheduler cannot hold a cancel until the tool starts.
  #
  # A cancel that arrives before a call opens is issued at the call's first
  # instruction, and only a scheduler that implements `fiber_interrupt` can
  # be asked for a raise from there - it schedules the raise rather than
  # issuing it. A scheduler that cannot is told so, rather than delivering
  # the cancel before the call and never running the tool.
  #
  # **Name it in full.** Ruby has a `FiberError` of its own, so a bare
  # `FiberError` in a rescue written outside this namespace is core's rather
  # than this one.
  FiberError = Class.new(Error)

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
