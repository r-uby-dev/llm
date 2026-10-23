# frozen_string_literal: true

class LLM::Google
  ##
  # The {LLM::Google::Images LLM::Google::Images} class provides an images
  # object for interacting with Google's Imagen text-to-image models via the
  # Imagen API: https://ai.google.dev/gemini-api/docs/imagen
  #
  # @example
  #   #!/usr/bin/env ruby
  #   require "llm"
  #   llm = LLM.google(key: ENV["KEY"])
  #   res = llm.images.create prompt: "A dog on a rocket to the moon"
  #   IO.copy_stream res.images[0], "rocket.png"
  class Images
    include RequestAdapter

    ##
    # Returns a new Images object
    # @param llm [LLM::Provider]
    # @return [LLM::Google::Images]
    def initialize(llm)
      @llm = llm
    end

    ##
    # Create an image
    # @example
    #   llm = LLM.google(key: ENV["KEY"])
    #   res = llm.images.create prompt: "A dog on a rocket to the moon"
    #   IO.copy_stream res.images[0], "rocket.png"
    # @see https://ai.google.dev/gemini-api/docs/imagen Imagen docs
    # @param [String] prompt The prompt
    # @param [Integer] n The number of images to generate
    # @param [String] image_size The size of the image ("1K", "2K", etc.)
    # @param [String] aspect_ratio The aspect ratio of the image ("1:1", "16:9", etc.)
    # @param [String] person_generation Allow the model to generate images of people ("dont_allow", "allow_adult", "allow_all")
    # @param [String] model The model to use
    # @param [Hash] params Other parameters (see Imagen docs)
    # @raise (see LLM::Provider#request)
    # @return [LLM::Response]
    def create(prompt:, n: 1, image_size: nil, aspect_ratio: nil, person_generation: nil, model: "imagen-4.0-generate-001", **params)
      req  = LLM::Transport::Request.post("/v1beta/models/#{model}:predict?key=#{key}", headers)
      body = LLM.json.dump({
        parameters: {
          sampleCount: n,
          imageSize: image_size,
          aspectRatio: aspect_ratio,
          personGeneration: person_generation
        }.compact.merge!(params),
        instances: [{prompt:}]
      })
      req.body = body
      res, span, tracer, request_id = execute(request: req, operation: "request")
      res = ResponseAdapter.adapt(res, type: :image)
      tracer.on_request_finish(operation: "request", model:, res:, span:, request_id:)
      res
    end

    ##
    # Edit an image
    # @example
    #   llm = LLM.google(key: ENV["KEY"])
    #   res = llm.images.edit image: "cat.png", prompt: "Add a hat to the cat"
    #   IO.copy_stream res.images[0], "hatoncat.png"
    # @see https://ai.google.dev/gemini-api/docs/image-generation Gemini docs
    # @param [String, LLM::File] image The image to edit
    # @param [String] prompt The prompt
    # @param [Hash] params Other parameters (see Gemini docs)
    # @raise (see LLM::Provider#request)
    # @note (see LLM::Google::Images#create)
    # @return [LLM::Response]
    def edit(image:, prompt:, model: "gemini-2.5-flash-image", **params)
      raise NotImplementedError, "image editing is not yet supported by Gemini"
    end

    ##
    # @raise [NotImplementedError]
    #  This method is not implemented by Gemini
    def create_variation
      raise NotImplementedError
    end

    private

    def adapter
      @adapter ||= Completion.new(nil)
    end

    def key
      @llm.instance_variable_get(:@key)
    end

    [:headers, :execute].each do |m|
      define_method(m) { |*args, **kwargs, &b| @llm.send(m, *args, **kwargs, &b) }
    end
  end
end
