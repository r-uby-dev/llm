# frozen_string_literal: true

class LLM::Transport
  ##
  # Internal request execution methods for {LLM::Provider}.
  #
  # This module handles provider-side transport execution, response
  # parsing, streaming, and request body setup.
  #
  # @api private
  module Execution
    private

    ##
    # Executes a HTTP request
    # @param [LLM::Transport::Request] request
    #  The request to send
    # @param [Proc] b
    #  A block to yield the response to (optional)
    # @return [LLM::Transport::Response]
    #  The response from the server
    # @raise [LLM::Error::Unauthorized]
    #  When authentication fails
    # @raise [LLM::Error::RateLimit]
    #  When the rate limit is exceeded
    # @raise [LLM::Error]
    #  When any other unsuccessful status code is returned
    # @raise [SystemCallError]
    #  When there is a network error at the operating system level
    # @return [LLM::Transport::Response]
    def execute(request:, operation:, stream: nil, stream_parser: self.stream_parser, model: nil, inputs: nil, &b)
      stream = nil if !stream&.enabled?
      stream &&= LLM::Object.from(streamer: stream, parser: stream_parser, decoder: stream_decoder)
      owner = transport.request_owner
      tracer = self.tracer
      request_id = SecureRandom.uuid_v7
      span = tracer.on_request_start(operation:, model:, inputs:, request_id:)
      res = transport.request(request, owner:, stream:, &b)
      res = LLM::Transport::Response.from(res)
      [handle_response(res, tracer, span, request_id), span, tracer, request_id]
    rescue LLM::Interrupt
      ##
      # An interrupt is not a failure, so it is not reported as
      # one: the tracer has a hook of its own for it, and it is
      # called before the caller is given the exception.
      tracer.on_interrupt(scope: :request, span:, request_id:)
      raise
    rescue *transport.interrupt_errors => ex
      ##
      # Where a Net::HTTP interrupt becomes the exception the
      # caller gets: the socket is closed from another thread
      # and the read fails as one of these classes. The owner
      # is what tells the two apart.
      if transport.interrupted?(owner)
        tracer.on_interrupt(scope: :request, span:, request_id:)
        raise LLM::Interrupt, "request interrupted"
      else
        tracer.on_request_error(ex:, span:, request_id:)
        raise
      end
    rescue => ex
      ##
      # Everything else ends the request, so the tracer is told:
      # a span that was opened and never closed draws a request
      # that never ended.
      tracer.on_request_error(ex:, span:, request_id:)
      raise
    end

    ##
    # Handles the response from a request
    # @param [LLM::Transport::Response] res
    #  The response to handle
    # @param [Object, nil] span
    #  The span
    # @param [String] request_id
    #  The id of the request being handled
    # @return [LLM::Transport::Response]
    def handle_response(res, tracer, span, request_id)
      res.ok? ? res.body = parse_response(res) :
                           error_handler.new(tracer, span, res, request_id).raise_error!
      res
    end

    ##
    # Parse a HTTP response
    # @param [LLM::Transport::Response] res
    # @return [LLM::Object, String]
    def parse_response(res)
      case res["content-type"]
      when %r{\Aapplication/json\s*}
        body = read_body(res.body)
        LLM::Object.from(LLM.json.load(body))
      else res.body
      end
    end

    ##
    # @param [#class] body
    # @return [String]
    def read_body(body)
      case body.class.to_s
      when "Net::ReadAdapter"
        str = +""
        body.read_body { str << _1 }
        str
      else body
      end
    end
  end
end
