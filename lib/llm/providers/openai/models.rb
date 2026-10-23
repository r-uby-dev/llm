# frozen_string_literal: true

class LLM::OpenAI
  ##
  # The {LLM::OpenAI::Models LLM::OpenAI::Models} class provides a model
  # object for interacting with [OpenAI's models API](https://platform.openai.com/docs/api-reference/models/list).
  # The models API allows a client to query OpenAI for a list of models
  # that are available for use with the OpenAI API.
  #
  # @example
  #   #!/usr/bin/env ruby
  #   require "llm"
  #
  #   llm = LLM.openai(key: ENV["KEY"])
  #   res = llm.models.all
  #   res.each do |model|
  #     print "id: ", model.id, "\n"
  #   end
  class Models
    ##
    # Returns a new Models object
    # @param llm [LLM::Provider]
    # @return [LLM::OpenAI::Files]
    def initialize(llm)
      @llm = llm
    end

    ##
    # List all models
    # @example
    #   llm = LLM.openai(key: ENV["KEY"])
    #   res = llm.models.all
    #   res.each do |model|
    #     print "id: ", model.id, "\n"
    #   end
    # @see https://platform.openai.com/docs/api-reference/models/list OpenAI docs
    # @param [Hash] params Other parameters (see OpenAI docs)
    # @raise (see LLM::Provider#request)
    # @return [LLM::Response]
    def all(**params)
      query = URI.encode_www_form(params)
      req = LLM::Transport::Request.get(path("/models?#{query}"), headers)
      res, span, tracer, request_id = execute(request: req, operation: "request")
      res = ResponseAdapter.adapt(res, type: :models)
      tracer.on_request_finish(operation: "request", res:, span:, request_id:)
      res
    end

    private

    [:path, :headers, :execute].each do |m|
      define_method(m) { |*args, **kwargs, &b| @llm.send(m, *args, **kwargs, &b) }
    end
  end
end
