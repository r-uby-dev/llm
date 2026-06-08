# frozen_string_literal: true

class LLM::Bedrock
  ##
  # Handles Bedrock API error responses.
  #
  # Bedrock errors come as JSON with:
  #   { "message" => "...", "__type" => "..." }
  # or as standard HTTP status codes.
  #
  # @api private
  class ErrorHandler
    ##
    # @return [LLM::Transport::Response]
    attr_reader :res

    ##
    # @return [Object, nil]
    attr_reader :span

    ##
    # @param [LLM::Tracer] tracer
    # @param [Object, nil] span
    # @param [LLM::Transport::Response, Net::HTTPResponse] res
    # @return [LLM::Bedrock::ErrorHandler]
    def initialize(tracer, span, res)
      @tracer = tracer
      @span = span
      @res = LLM::Transport::Response.from(res)
    end

    ##
    # @raise [LLM::Error]
    def raise_error!
      ex = error
      @tracer.on_request_error(ex:, span:)
    ensure
      raise(ex) if ex
    end

    private

    ##
    # @return [LLM::Error]
    def error
      message = extract_message
      if res.server_error?
        LLM::ServerError.new(message).tap { _1.response = res }
      elsif res.unauthorized?
        LLM::UnauthorizedError.new(message).tap { _1.response = res }
      elsif res.forbidden?
        LLM::UnauthorizedError.new(message).tap { _1.response = res }
      elsif res.rate_limited?
        LLM::RateLimitError.new(message).tap { _1.response = res }
      elsif res.not_found?
        LLM::NotFoundError.new("Server response: not found (404)").tap { _1.response = res }
      else
        LLM::Error.new(message).tap { _1.response = res }
      end
    end

    ##
    # @return [String]
    def extract_message
      body = parse_body
      body["message"] || body["Message"] || body["__type"] || "Unexpected error"
    end

    ##
    # @return [Hash]
    def parse_body
      return {} if res.body.nil? || res.body.empty?
      parsed = LLM.json.load(res.body.dup.force_encoding(Encoding::UTF_8).scrub)
      Hash === parsed ? parsed : {}
    rescue *LLM.json.parser_error
      {}
    end
  end
end
