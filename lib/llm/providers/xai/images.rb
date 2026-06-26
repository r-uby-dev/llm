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
    # @api private
    PATTERN = %r{\A(?:https?://|data:)}
    private_constant :PATTERN

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
    def create(prompt:, model: "grok-imagine-image-quality", **params)
      req = LLM::Transport::Request.post(path("/images/generations"), headers)
      req.body = LLM.json.dump({prompt:, n: 1, model:, response_format: "b64_json"}.merge!(params))
      res, span, tracer = execute(request: req, operation: "request")
      res = LLM::OpenAI::ResponseAdapter.adapt(res, type: :image)
      tracer.on_request_finish(operation: "request", model:, res:, span:)
      res
    end

    ##
    # Edit an image
    # @example
    #   llm = LLM.xai(key: ENV["KEY"])
    #   res = llm.images.edit(image: "/images/book.png", prompt: "The book is floating in the clouds")
    #   IO.copy_stream res.images[0], "floating-book.png"
    # @see https://docs.x.ai/docs/guides/image-generations xAI docs
    # @param [String, LLM::File, File] image The image to edit
    # @param [String] prompt The prompt
    # @param [String] model The model to use
    # @param [Hash] params Other parameters (see xAI docs)
    # @raise (see LLM::Provider#request)
    # @return [LLM::Response]
    def edit(image:, prompt:, model: "grok-imagine-image-quality", **params)
      req = LLM::Transport::Request.post(path("/images/edits"), headers)
      req.body = LLM.json.dump({
        prompt:,
        model:,
        image: image_url(image),
        response_format: "b64_json"
      }.merge!(params))
      res, span, tracer = execute(request: req, operation: "request")
      res = LLM::OpenAI::ResponseAdapter.adapt(res, type: :image)
      tracer.on_request_finish(operation: "request", model:, res:, span:)
      res
    end

    private

    def image_url(image)
      case image
      when String
        url = image.match?(PATTERN) ? image : LLM.File(image).to_data_uri
      else
        url = LLM.File(image).to_data_uri
      end
      {url:, type: "image_url"}
    end
  end
end
