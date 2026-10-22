# frozen_string_literal: true

class LLM::Transport
  ##
  # {LLM::Transport::Response LLM::Transport::Response} defines the
  # normalized HTTP response interface expected by transports and
  # provider error handlers.
  #
  # Custom transports can execute requests through any underlying HTTP
  # client, then adapt that client's native response object to this
  # interface.
  #
  # This keeps the transport boundary focused on one contract:
  # providers, execution, and error handlers only need a response
  # object that implements
  # {LLM::Transport::Response LLM::Transport::Response}, regardless of
  # how the request was actually performed.
  class Response
    require_relative "response/http"

    ##
    # @param [Object] res
    # @return [LLM::Transport::Response]
    def self.from(res)
      return res if LLM::Transport::Response === res
      return HTTP.new(res) if Net::HTTPResponse === res
      res
    end

    ##
    # @return [String]
    def code
      raise NotImplementedError
    end

    ##
    # @return [Object]
    def body
      raise NotImplementedError
    end

    ##
    # @param [Object] value
    # @return [Object]
    def body=(value)
      raise NotImplementedError
    end

    ##
    # @param [String] key
    # @return [String, nil]
    def [](key)
      raise NotImplementedError
    end

    ##
    # @param [Object, nil] dest
    # @yieldparam [String] chunk
    # @return [void]
    def read_body(dest = nil, &)
      raise NotImplementedError
    end

    ##
    # @return [Boolean]
    def success?
      raise NotImplementedError
    end

    ##
    # @return [Boolean]
    def ok?
      raise NotImplementedError
    end

    ##
    # @return [Boolean]
    def bad_request?
      raise NotImplementedError
    end

    ##
    # @return [Boolean]
    def unauthorized?
      raise NotImplementedError
    end

    ##
    # @return [Boolean]
    def forbidden?
      raise NotImplementedError
    end

    ##
    # @return [Boolean]
    def not_found?
      raise NotImplementedError
    end

    ##
    # @return [Boolean]
    def rate_limited?
      raise NotImplementedError
    end

    ##
    # @return [Boolean]
    def server_error?
      raise NotImplementedError
    end
  end
end
