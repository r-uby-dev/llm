# frozen_string_literal: true

class LLM::DeepInfra
  ##
  # The {LLM::DeepInfra::Images LLM::DeepInfra::Images} class provides an
  # interface for [DeepInfra's images API](https://docs.deepinfra.com/apis/image-generation).
  # DeepInfra returns base64-encoded image data.
  #
  # @example
  #   #!/usr/bin/env ruby
  #   require "llm"
  #
  #   llm = LLM.deepinfra(key: ENV["KEY"])
  #   res = llm.images.create prompt: "A dog on a rocket to the moon"
  #   IO.copy_stream res.images[0], "rocket.png"
  class Images
    ##
    # @param [LLM::Provider] provider
    # @return [LLM::DeepInfra::Images]
    def initialize(provider)
      @provider = provider
    end

    ##
    # @see https://deepinfra.com/models/text-to-image DeepInfra Image Models
    # @param [String] prompt
    #  A prompt
    # @param [String] model
    #  A text-to-image model.
    #  Defaults to the black-forest-labs/FLUX-2-klein-4b.
    # @param [String] size
    #  Image size (eg 1024x1024)
    # @param [Integer] n
    #  The number of images to default
    # @param [String] response_format
    #  No other options other than the default are supported.
    # @param [String] quality
    #  Exists for compat. Noop.
    # @param [String] style
    #  Exists for compat. Noop.
    # @return [LLM::Response<LLM::OpenAI::ResponseAdapter::Image>]
    #  Returns a response
    def create(prompt:, model: "black-forest-labs/FLUX-2-klein-4b", size: "1024x1024", n: 1, response_format: "b64_json", quality: nil, style: nil)
      req = LLM::Transport::Request.post(path("/images/generations"), headers)
      params = {prompt:, model:, size:, n:, response_format:, quality:, style:}.compact
      req.body = LLM.json.dump(params)
      res, span, tracer = execute(request: req, operation: "request")
      res = LLM::OpenAI::ResponseAdapter.adapt(res, type: :image)
      tracer.on_request_finish(operation: "request", model:, res:, span:)
      res
    end

    ##
    # @see https://deepinfra.com/models/text-to-image DeepInfra Image Models
    # @param [String, LLM::File, File] image
    #  The image to edit.
    # @param [String] prompt
    #  A text description of the desired edits.
    # @param [String] model
    #  The model to use.
    # @param [String] size
    #  Image size (eg 1024x1024)
    # @param [Integer] n
    #  The number of images to generate.
    # @param [String] response_format
    #  DeepInfra currently supports b64_json.
    # @param [Hash] params
    #  Other parameters supported by DeepInfra, such as :mask or :user.
    # @return [LLM::Response<LLM::OpenAI::ResponseAdapter::Image>]
    #  Returns a response
    def edit(image:, prompt:, model: "black-forest-labs/FLUX-2-klein-4b", size: "1024x1024", n: 1, response_format: "b64_json", **params)
      params = params.merge!(image: LLM.File(image), prompt:, model:, size:, n:, response_format:)
      params[:mask] = LLM.File(params[:mask]) if params[:mask]
      multi = LLM::Multipart.new(params)
      req = LLM::Transport::Request.post(path("/images/edits"), headers)
      req["content-type"] = multi.content_type
      transport.set_body_stream(req, multi.body)
      res, span, tracer = execute(request: req, operation: "request")
      res = LLM::OpenAI::ResponseAdapter.adapt(res, type: :image)
      tracer.on_request_finish(operation: "request", model:, res:, span:)
      res
    end

    private

    [:path, :headers, :execute, :transport].each do |m|
      define_method(m) { |*args, **kwargs, &b| @provider.send(m, *args, **kwargs, &b) }
    end
  end
end
