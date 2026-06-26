# frozen_string_literal: true

class LLM::XAI
  ##
  # The {LLM::XAI::Images LLM::XAI::Images} class provides an interface
  # for [xAI's images API](https://docs.x.ai/docs/guides/image-generations).
  # xAI returns base64-encoded image data.
  #
  # @example
  #   #!/usr/bin/env ruby
  #   require "llm"
  #
  #   llm = LLM.xai(key: ENV["KEY"])
  #   res = llm.images.create prompt: "A dog on a rocket to the moon"
  #   IO.copy_stream res.images[0], "rocket.png"
  class Images < LLM::OpenAI::Images
    ##
    # Create an image
    # @example
    #   llm = LLM.xai(key: ENV["KEY"])
    #   res = llm.images.create prompt: "A dog on a rocket to the moon"
    #   IO.copy_stream res.images[0], "rocket.png"
    # @see https://docs.x.ai/docs/guides/image-generations xAI docs
    # @param [String] prompt The prompt
    # @param [String] model The model to use
    # @param [Hash] params Other parameters (see xAI docs)
    # @raise (see LLM::Provider#request)
    # @return [LLM::Response]
    def create(prompt:, model: "grok-imagine-image", **params)
      req = LLM::Transport::Request.post(path("/images/generations"), headers)
      req.body = LLM.json.dump({prompt:, n: 1, model:, response_format: "b64_json"}.merge!(params))
      res, span, tracer = execute(request: req, operation: "request")
      res = LLM::OpenAI::ResponseAdapter.adapt(res, type: :image)
      tracer.on_request_finish(operation: "request", model:, res:, span:)
      res
    end

    ##
    # @raise [NotImplementedError]
    def edit(model: "grok-imagine-image", **)
      raise NotImplementedError
    end
  end
end
