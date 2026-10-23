# frozen_string_literal: true

class LLM::DeepInfra
  class Audio
    ##
    # @param [LLM::Provider] llm
    #  A provider
    # @return [LLM::DeepInfra::Audio]
    def initialize(llm)
      @llm = llm
    end

    ##
    # @param [String] input
    #  A string of text
    # @param [String] model
    #  A text-to-speech model.
    #  Defaults to hexgrad/Kokoro-82M.
    # @param [Hash] params
    #  Any other model-specific parameters
    # @return [LLM::Response]
    def create_speech(input:, model: "hexgrad/Kokoro-82M", **params)
      path = path("/v1/inference/#{model}", base_path: false)
      req = LLM::Transport::Request.post(path, headers)
      req.body = JSON.dump(params.merge(text: input))
      res, span, tracer, request_id = execute(request: req, operation: "request")
      res = ResponseAdapter.adapt LLM::Response.new(res), type: :audio
      tracer.on_request_finish(operation: "request", model:, res:, span:, request_id:)
      res
    end

    ##
    # @see https://deepinfra.com/models/automatic-speech-recognition speech-to-text models
    # @see https://docs.deepinfra.com/apis/speech API docs
    # @param [String, LLM::File] file
    #  An audio file
    # @param [String] model
    #  A speech-to-text model.
    # @param [Hash] params
    #  Any other model-specific parameters
    # @return [LLM::Response]
    def create_transcription(file:, model: "openai/whisper-large-v3", **params)
      path = path("/v1/inference/#{model}", base_path: false)
      multi = LLM::Multipart.new(params.merge!(audio: LLM.File(file)))
      req = LLM::Transport::Request.post(path, headers)
      req["content-type"] = multi.content_type
      transport.set_body_stream(req, multi.body)
      res, span, tracer, request_id = execute(request: req, operation: "request")
      res = LLM::Response.new(res)
      tracer.on_request_finish(operation: "request", model:, res:, span:, request_id:)
      res
    end

    ##
    # @raise [NotImplementedError]
    def create_translation(...)
      raise NotImplementedError
    end

    private

    [:path, :headers, :execute, :transport].each do |m|
      define_method(m) { |*args, **kwargs, &b| @llm.send(m, *args, **kwargs, &b) }
    end
  end
end
