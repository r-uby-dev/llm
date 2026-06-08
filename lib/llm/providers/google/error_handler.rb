# frozen_string_literal: true

class LLM::Google
  ##
  # @private
  class ErrorHandler
    ##
    # @return [LLM::Transport::Response]
    #  Non-2XX response from the server
    attr_reader :res

    ##
    # @return [Object, nil]
    #  The span
    attr_reader :span

    ##
    # @param [LLM::Tracer] tracer
    #  The tracer
    # @param [Object, nil] span
    #  The span
    # @param [LLM::Transport::Response, Net::HTTPResponse] res
    #  The response from the server
    # @return [LLM::Google::ErrorHandler]
    def initialize(tracer, span, res)
      @tracer = tracer
      @span = span
      @res = LLM::Transport::Response.from(res)
    end

    ##
    # @raise [LLM::Error]
    #  Raises a subclass of {LLM::Error LLM::Error}
    def raise_error!
      ex = error
      @tracer.on_request_error(ex:, span:)
    ensure
      raise(ex) if ex
    end

    private

    ##
    # @return [String, LLM::Object]
    def body
      @body ||= parse_body!
    end

    ##
    # @return [LLM::Error]
    def error
      if res.server_error?
        LLM::ServerError.new("Server error").tap { _1.response = res }
      elsif res.bad_request?
        reason = body.dig("error", "details", 0, "reason")
        if reason == "API_KEY_INVALID"
          LLM::UnauthorizedError.new("Authentication error").tap { _1.response = res }
        else
          LLM::Error.new("Unexpected response").tap { _1.response = res }
        end
      elsif res.rate_limited?
        LLM::RateLimitError.new("Too many requests").tap { _1.response = res }
      elsif res.not_found?
        LLM::NotFoundError.new("Server response: not found (404)").tap { _1.response = res }
      else
        LLM::Error.new("Unexpected response").tap { _1.response = res }
      end
    end

    ##
    # Tries to parse the response body as a LLM::Object
    # @return [String, LLM::Object]
    def parse_body!
      if String === res.body
        LLM::Object.from LLM.json.load(res.body)
      elsif Hash === res.body
        LLM::Object.from(res.body)
      else
        res.body
      end
    rescue
      res.body
    end
  end
end
