# frozen_string_literal: true

module LLM
  ##
  # {LLM::Response LLM::Response} is the normalized base shape for
  # provider and endpoint responses in llm.rb.
  #
  # Provider calls return an instance of this class, then extend it
  # with provider-, endpoint-, or context-specific modules so response
  # handling can share one common surface without flattening away
  # specialized behavior.
  #
  # The normalized response keeps the transport response available
  # through {#res}. When the default net/http transport is in use,
  # {LLM::Transport::Response::HTTP
  # LLM::Transport::Response::HTTP} keeps the
  # original `Net::HTTPResponse` available through
  # its own {LLM::Transport::Response::HTTP#res #res}.
  class Response
    require "json"

    ##
    # Returns the HTTP response
    # @return [LLM::Transport::Response]
    attr_reader :res

    ##
    # @param [LLM::Transport::Response] res
    #  HTTP response
    # @return [LLM::Response]
    #  Returns an instance of LLM::Response
    def initialize(res)
      @res = LLM::Transport::Response.from(res)
    end

    ##
    # Returns the response body
    # @return [LLM::Object, String]
    #  Returns an LLM::Object when the response body is JSON,
    #  otherwise returns a raw string.
    def body
      @res.body
    end

    ##
    # Returns an inspection of the response object
    # @return [String]
    def inspect
      "#<#{LLM::Utils.object_id(self)} @body=#{body.inspect} @res=#{@res.inspect}>"
    end

    ##
    # Returns true if the response is successful
    # @return [Boolean]
    def ok?
      @res.success?
    end

    ##
    # Returns true if the response is from the Files API
    # @return [Boolean]
    def file?
      false
    end

    private

    def method_missing(m, *args, **kwargs, &b)
      if LLM::Object === body
        body.respond_to?(m) ? body[m.to_s] : super
      else
        super
      end
    end

    def respond_to_missing?(m, include_private = false)
      if LLM::Object === body
        body.respond_to?(m)
      else
        false
      end
    end
  end
end
