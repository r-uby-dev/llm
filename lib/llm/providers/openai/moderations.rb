# frozen_string_literal: true

class LLM::OpenAI
  ##
  # The {LLM::OpenAI::Moderations LLM::OpenAI::Moderations} class provides a moderations
  # object for interacting with [OpenAI's moderations API](https://platform.openai.com/docs/api-reference/moderations).
  # The moderations API can categorize content into different categories, such as
  # hate speech, self-harm, and sexual content. It can also provide a confidence score
  # for each category.
  #
  # @example
  #   #!/usr/bin/env ruby
  #   require "llm"
  #
  #   llm = LLM.openai(key: ENV["KEY"])
  #   res = llm.moderations.create input: "I hate you"
  #   mod = res.moderations[0]
  #   print "categories: #{mod.categories}", "\n"
  #   print "scores: #{mod.scores}", "\n"
  #
  # @example
  #   #!/usr/bin/env ruby
  #   require "llm"
  #
  #   llm = LLM.openai(key: ENV["KEY"])
  #   res = llm.moderations.create input: URI.parse("https://example.com/image.png")
  #   mod = res.moderations[0]
  #   print "categories: #{mod.categories}", "\n"
  #   print "scores: #{mod.scores}", "\n"
  #
  # @see https://platform.openai.com/docs/api-reference/moderations/create OpenAI docs
  # @see https://platform.openai.com/docs/models#moderation OpenAI moderation models
  class Moderations
    ##
    # Returns a new Moderations object
    # @param [LLM::Provider] llm
    # @return [LLM::OpenAI::Moderations]
    def initialize(llm)
      @llm = llm
    end

    ##
    # Create a moderation
    # @see https://platform.openai.com/docs/api-reference/moderations/create OpenAI docs
    # @see https://platform.openai.com/docs/models#moderation OpenAI moderation models
    # @param [String, URI, Array<String, URI>] input
    # @param [String, LLM::Model] model The model to use
    # @return [LLM::Response]
    def create(input:, model: "omni-moderation-latest", **params)
      req = LLM::Transport::Request.post(path("/moderations"), headers)
      input = RequestAdapter::Moderation.new(input).adapt
      req.body = LLM.json.dump({input:, model:}.merge!(params))
      res, span, tracer, request_id = execute(request: req, operation: "request")
      res = ResponseAdapter.adapt(res, type: :moderations)
      tracer.on_request_finish(operation: "request", model:, res:, span:, request_id:)
      res
    end

    private

    [:path, :headers, :execute].each do |m|
      define_method(m) { |*args, **kwargs, &b| @llm.send(m, *args, **kwargs, &b) }
    end
  end
end
