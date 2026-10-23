# frozen_string_literal: true

class LLM::Google
  ##
  # The {LLM::Google::Models LLM::Google::Models} class provides a model
  # object for interacting with [Gemini's models API](https://ai.google.dev/api/models?hl=en#method:-models.list).
  # The models API allows a client to query Gemini for a list of models
  # that are available for use with the Gemini API.
  #
  # @example
  #   #!/usr/bin/env ruby
  #   require "llm"
  #
  #   llm = LLM.google(key: ENV["KEY"])
  #   res = llm.models.all
  #   res.each do |model|
  #     print "id: ", model.id, "\n"
  #   end
  class Models
    ##
    # Returns a new Models object
    # @param llm [LLM::Provider]
    # @return [LLM::Google::Models]
    def initialize(llm)
      @llm = llm
    end

    ##
    # List all models
    # @example
    #   llm = LLM.google(key: ENV["KEY"])
    #   res = llm.models.all
    #   res.each do |model|
    #     print "id: ", model.id, "\n"
    #   end
    # @see https://ai.google.dev/api/models?hl=en#method:-models.list Gemini docs
    # @param [Hash] params Other parameters (see Gemini docs)
    # @raise (see LLM::Provider#request)
    # @return [LLM::Response]
    def all(**params)
      query = URI.encode_www_form(params.merge!(key: key))
      req = LLM::Transport::Request.get("/v1beta/models?#{query}", headers)
      res, span, tracer, request_id = execute(request: req, operation: "request")
      res = ResponseAdapter.adapt(res, type: :models)
      tracer.on_request_finish(operation: "request", res:, span:, request_id:)
      res
    end

    private

    def key
      @llm.instance_variable_get(:@key)
    end

    [:headers, :execute].each do |m|
      define_method(m) { |*args, **kwargs, &b| @llm.send(m, *args, **kwargs, &b) }
    end
  end
end
