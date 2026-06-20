# frozen_string_literal: true

class LLM::Transport::Response
  ##
  # {LLM::Transport::Response::HTTP LLM::Transport::Response::HTTP}
  # adapts a `Net::HTTPResponse` to the
  # {LLM::Transport::Response LLM::Transport::Response} interface.
  #
  # This is the default wrapper for responses produced by the built-in
  # {LLM::Transport::HTTP LLM::Transport::HTTP} transport.
  class HTTP < self
    ##
    # @return [Net::HTTPResponse]
    attr_reader :res

    ##
    # @param [Net::HTTPResponse] res
    # @return [LLM::Transport::Response::HTTP]
    def initialize(res)
      @res = res
    end

    ##
    # @return [String]
    def code
      @res.code
    end

    ##
    # @return [Object]
    def body
      @res.body
    end

    ##
    # @param [Object] value
    # @return [Object]
    def body=(value)
      @res.body = value
    end

    ##
    # @param [String] key
    # @return [String, nil]
    def [](key)
      @res[key]
    end

    ##
    # @param [Object, nil] dest
    # @yieldparam [String] chunk
    # @return [void]
    def read_body(dest = nil, &block)
      if dest && block
        @res.read_body(dest) { block.call(_1) }
      elsif dest
        @res.read_body(dest)
      elsif block
        @res.read_body { block.call(_1) }
      else
        @res.read_body
      end
    end

    ##
    # @return [Boolean]
    def success?
      Net::HTTPSuccess === @res
    end

    ##
    # @return [Boolean]
    def ok?
      Net::HTTPOK === @res
    end

    ##
    # @return [Boolean]
    def bad_request?
      Net::HTTPBadRequest === @res
    end

    ##
    # @return [Boolean]
    def unauthorized?
      Net::HTTPUnauthorized === @res
    end

    ##
    # @return [Boolean]
    def forbidden?
      Net::HTTPForbidden === @res
    end

    ##
    # @return [Boolean]
    def not_found?
      Net::HTTPNotFound === @res
    end

    ##
    # @return [Boolean]
    def rate_limited?
      Net::HTTPTooManyRequests === @res
    end

    ##
    # @return [Boolean]
    def server_error?
      Net::HTTPServerError === @res
    end
  end
end
