# frozen_string_literal: true

require_relative "openai" unless defined?(LLM::OpenAI)

module LLM
  ##
  # The CheaperInference class implements a provider for
  # [Cheaper Inference](https://cheaperinference.com) through its
  # OpenAI-compatible API.
  #
  # @example
  #   #!/usr/bin/env ruby
  #   require "llm"
  #
  #   llm   = LLM.cheaperinference
  #   agent = LLM::Agent.new(llm)
  #   agent.talk "hello world", stream: $stdout
  class CheaperInference < OpenAI
    HOST = "api.cheaperinference.com"
    BASE_PATH = "/v1"

    ##
    # @param key (see LLM::Provider#initialize)
    # @param host (see LLM::Provider#initialize)
    # @param base_path (see LLM::Provider#initialize)
    # @return [LLM::CheaperInference]
    def initialize(host: HOST, base_path: BASE_PATH, port: 443, ssl: true, **)
      super
    end

    ##
    # Returns the provider's name
    # @return [Symbol]
    def name
      :cheaperinference
    end

    ##
    # @raise [NotImplementedError]
    def files
      raise NotImplementedError
    end

    ##
    # @raise [NotImplementedError]
    def images
      raise NotImplementedError
    end

    ##
    # @raise [NotImplementedError]
    def audio
      raise NotImplementedError
    end

    ##
    # @raise [NotImplementedError]
    def moderations
      raise NotImplementedError
    end

    ##
    # @raise [NotImplementedError]
    def vector_stores
      raise NotImplementedError
    end

    ##
    # Returns the default model for chat completions
    # @see https://cheaperinference.com/docs Cheaper Inference docs
    # @return [String]
    def default_model
      "gpt-5.4-mini"
    end
  end
end
