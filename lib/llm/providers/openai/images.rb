# frozen_string_literal: true

class LLM::OpenAI
  ##
  # The {LLM::OpenAI::Images LLM::OpenAI::Images} class provides an interface
  # for [OpenAI's images API](https://platform.openai.com/docs/api-reference/images).
  # OpenAI's GPT Image models return base64-encoded image data.
  #
  # @example
  #   #!/usr/bin/env ruby
  #   require "llm"
  #
  #   llm = LLM.openai(key: ENV["KEY"])
  #   res = llm.images.create prompt: "A dog on a rocket to the moon"
  #   IO.copy_stream res.images[0], "rocket.png"
  class Images
    ##
    # Returns a new Images object
    # @param llm [LLM::Provider]
    # @return [LLM::OpenAI::Responses]
    def initialize(llm)
      @llm = llm
    end

    ##
    # Create an image
    # @example
    #   llm = LLM.openai(key: ENV["KEY"])
    #   res = llm.images.create prompt: "A dog on a rocket to the moon"
    #   IO.copy_stream res.images[0], "rocket.png"
    # @see https://platform.openai.com/docs/api-reference/images/create OpenAI docs
    # @param [String] prompt The prompt
    # @param [String] model The model to use
    # @param [String] output_format The output format ("png", "webp", or "jpeg")
    # @param [Hash] params Other parameters (see OpenAI docs)
    # @raise (see LLM::Provider#request)
    # @return [LLM::Response]
    def create(prompt:, model: "gpt-image-1-mini", output_format: "png", **params)
      req = LLM::Transport::Request.post(path("/images/generations"), headers)
      req.body = LLM.json.dump({prompt:, n: 1, model:, output_format:}.merge!(params))
      res, span, tracer, request_id = execute(request: req, operation: "request")
      res = ResponseAdapter.adapt(res, type: :image)
      tracer.on_request_finish(operation: "request", model:, res:, span:, request_id:)
      res
    end

    ##
    # Edit an image
    # @example
    #   llm = LLM.openai(key: ENV["KEY"])
    #   res = llm.images.edit(image: "/images/hat.png", prompt: "A cat wearing this hat")
    #   IO.copy_stream res.images[0], "hatoncat.png"
    # @see https://platform.openai.com/docs/api-reference/images/createEdit OpenAI docs
    # @param [File] image The image to edit
    # @param [String] prompt The prompt
    # @param [String] model The model to use
    # @param [String] output_format The output format ("png", "webp", or "jpeg")
    # @param [Hash] params Other parameters (see OpenAI docs)
    # @raise (see LLM::Provider#request)
    # @return [LLM::Response]
    def edit(image:, prompt:, model: "gpt-image-1-mini", output_format: "png", **params)
      image = LLM.File(image)
      multi = LLM::Multipart.new(params.merge!(image:, prompt:, model:, output_format:))
      req = LLM::Transport::Request.post(path("/images/edits"), headers)
      req["content-type"] = multi.content_type
      transport.set_body_stream(req, multi.body)
      res, span, tracer, request_id = execute(request: req, operation: "request")
      res = ResponseAdapter.adapt(res, type: :image)
      tracer.on_request_finish(operation: "request", model:, res:, span:, request_id:)
      res
    end

    private

    [:path, :headers, :execute, :transport].each do |m|
      define_method(m) { |*args, **kwargs, &b| @llm.send(m, *args, **kwargs, &b) }
    end
  end
end
