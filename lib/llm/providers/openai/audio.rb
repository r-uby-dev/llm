# frozen_string_literal: true

class LLM::OpenAI
  ##
  # The {LLM::OpenAI::Audio LLM::OpenAI::Audio} class provides an audio
  # object for interacting with [OpenAI's audio API](https://platform.openai.com/docs/api-reference/audio/createSpeech).
  # @example
  #   llm = LLM.openai(key: ENV["KEY"])
  #   res = llm.audio.create_speech(input: "A dog on a rocket to the moon")
  #   IO.copy_stream res.audio, "rocket.mp3"
  class Audio
    ##
    # Returns a new Audio object
    # @param llm [LLM::Provider]
    # @return [LLM::OpenAI::Responses]
    def initialize(llm)
      @llm = llm
    end

    ##
    # Create an audio track
    # @example
    #   llm = LLM.openai(key: ENV["KEY"])
    #   res = llm.images.create_speech(input: "A dog on a rocket to the moon")
    #   IO.copy_stream res.audio.decoded, "rocket.mp3"
    # @see https://platform.openai.com/docs/api-reference/audio/createSpeech OpenAI docs
    # @param [String] input The text input
    # @param [String] voice The voice to use
    # @param [String] model The model to use
    # @param [String] response_format The response format
    # @param [Hash] params Other parameters (see OpenAI docs)
    # @raise (see LLM::Provider#request)
    # @return [LLM::Response]
    def create_speech(input:, voice: "alloy", model: "gpt-4o-mini-tts", response_format: "mp3", **params)
      req = LLM::Transport::Request.post(path("/audio/speech"), headers)
      req.body = LLM.json.dump({input:, voice:, model:, response_format:}.merge!(params))
      io = StringIO.new("".b)
      res, span, tracer, request_id = execute(request: req, operation: "request") { _1.read_body { |chunk| io << chunk } }
      content_type = res["content-type"].to_s.split(";").first
      content_type = content_type.empty? ? LLM::Mime[".#{response_format}"] : content_type
      data = "data:#{content_type};base64,#{[io.string].pack("m0")}"
      res.body = LLM::Object.from(audio: data)
      res = ResponseAdapter.adapt(LLM::Response.new(res), type: :audio)
      tracer.on_request_finish(operation: "request", model:, res:, span:, request_id:)
      res
    end

    ##
    # Create an audio transcription
    # @example
    #   llm = LLM.openai(key: ENV["KEY"])
    #   res = llm.audio.create_transcription(file: "/audio/rocket.mp3")
    #   res.text # => "A dog on a rocket to the moon"
    # @see https://platform.openai.com/docs/api-reference/audio/createTranscription OpenAI docs
    # @param [String, LLM::File] file The input audio
    # @param [String] model The model to use
    # @param [Hash] params Other parameters (see OpenAI docs)
    # @raise (see LLM::Provider#request)
    # @return [LLM::Response]
    def create_transcription(file:, model: "whisper-1", **params)
      multi = LLM::Multipart.new(params.merge!(file: LLM.File(file), model:))
      req = LLM::Transport::Request.post(path("/audio/transcriptions"), headers)
      req["content-type"] = multi.content_type
      transport.set_body_stream(req, multi.body)
      res, span, tracer, request_id = execute(request: req, operation: "request")
      res = LLM::Response.new(res)
      tracer.on_request_finish(operation: "request", model:, res:, span:, request_id:)
      res
    end

    ##
    # Create an audio translation (in English)
    # @example
    #   # Arabic => English
    #   llm = LLM.openai(key: ENV["KEY"])
    #   res = llm.audio.create_translation(file: "/audio/bismillah.mp3")
    #   res.text # => "In the name of Allah, the Beneficent, the Merciful."
    # @see https://platform.openai.com/docs/api-reference/audio/createTranslation OpenAI docs
    # @param [LLM::File] file The input audio
    # @param [String] model The model to use
    # @param [Hash] params Other parameters (see OpenAI docs)
    # @raise (see LLM::Provider#request)
    # @return [LLM::Response]
    def create_translation(file:, model: "whisper-1", **params)
      multi = LLM::Multipart.new(params.merge!(file: LLM.File(file), model:))
      req = LLM::Transport::Request.post(path("/audio/translations"), headers)
      req["content-type"] = multi.content_type
      transport.set_body_stream(req, multi.body)
      res, span, tracer, request_id = execute(request: req, operation: "request")
      res = LLM::Response.new(res)
      tracer.on_request_finish(operation: "request", model:, res:, span:, request_id:)
      res
    end

    private

    [:path, :headers, :execute, :transport].each do |m|
      define_method(m) { |*args, **kwargs, &b| @llm.send(m, *args, **kwargs, &b) }
    end
  end
end
