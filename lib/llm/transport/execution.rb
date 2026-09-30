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
    rescue LLM::Interrupt => ex
      ##
      # A transport that raises the interrupt itself - curb
      # raises from the chunk it is reading - reaches here,
      # and the span closes before the caller sees it.
      tracer.on_request_error(ex:, span:, request_id:)
      raise
    rescue *transport.interrupt_errors => ex
      ##
      # A Net::HTTP request is interrupted by closing its
      # socket from another thread, so it fails here instead.
      # Either way the caller is given an interrupt, and the
      # tracer is told which request it ended.
      ex = LLM::Interrupt.new("request interrupted") if transport.interrupted?(owner)
      tracer.on_request_error(ex:, span:, request_id:)
      raise(ex)
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
