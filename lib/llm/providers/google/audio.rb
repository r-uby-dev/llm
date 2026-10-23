# frozen_string_literal: true

class LLM::Google
  ##
  # The {LLM::Google::Audio LLM::Google::Audio} class provides an audio
  # object for interacting with [Gemini's audio API](https://ai.google.dev/gemini-api/docs/audio).
  # @example
  #   #!/usr/bin/env ruby
  #   require "llm"
  #
  #   llm = LLM.google(key: ENV["KEY"])
  #   res = llm.audio.create_transcription(input: "/audio/rocket.mp3")
  #   res.text # => "A dog on a rocket to the moon"
  class Audio
    ##
    # Returns a new Audio object
    # @param llm [LLM::Provider]
    # @return [LLM::Google::Audio]
    def initialize(llm)
      @llm = llm
    end

    ##
    # @raise [NotImplementedError]
    #  This method is not implemented by Gemini
    def create_speech
      raise NotImplementedError
    end

    ##
    # Create an audio transcription
    # @example
    #   llm = LLM.google(key: ENV["KEY"])
    #   res = llm.audio.create_transcription(file: "/audio/rocket.mp3")
    #   res.text # => "A dog on a rocket to the moon"
    # @see https://ai.google.dev/gemini-api/docs/audio Gemini docs
    # @param [String, LLM::File, LLM::Response] file The input audio
    # @param [String] model The model to use
    # @param [Hash] params Other parameters (see Gemini docs)
    # @raise (see LLM::Provider#request)
    # @return [LLM::Response]
    def create_transcription(file:, model: @llm.default_model, **params)
      res = @llm.complete [
        "Your task is to transcribe the contents of an audio file",
        "Your response should include the transcription, and nothing else",
        LLM::Object.from(value: LLM.File(file), kind: :local_file)
      ], params.merge(role: :user, model:)
      res.tap { _1.define_singleton_method(:text) { choices[0].content } }
    end

    ##
    # Create an audio translation (in English)
    # @example
    #   # Arabic => English
    #   llm = LLM.google(key: ENV["KEY"])
    #   res = llm.audio.create_translation(file: "/audio/bismillah.mp3")
    #   res.text # => "In the name of Allah, the Beneficent, the Merciful."
    # @see https://ai.google.dev/gemini-api/docs/audio Gemini docs
    # @param [String, LLM::File, LLM::Response] file The input audio
    # @param [String] model The model to use
    # @param [Hash] params Other parameters (see Gemini docs)
    # @raise (see LLM::Provider#request)
    # @return [LLM::Response]
    def create_translation(file:, model: @llm.default_model, **params)
      res = @llm.complete [
        "Your task is to translate the contents of an audio file into English",
        "Your response should include the translation, and nothing else",
        LLM::Object.from(value: LLM.File(file), kind: :local_file)
      ], params.merge(role: :user, model:)
      res.tap { _1.define_singleton_method(:text) { choices[0].content } }
    end
  end
end
