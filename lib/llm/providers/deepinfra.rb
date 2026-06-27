# frozen_string_literal: true

require_relative "openai" unless defined?(LLM::OpenAI)

module LLM
  ##
  # The DeepInfra class implements a provider for
  # [DeepInfra](https://deepinfra.com)
  # through its OpenAI-compatible API.
  #
  # @example
  #   #!/usr/bin/env ruby
  #   require "llm"
  #
  #   llm = LLM.deepinfra(key: ENV["KEY"])
  #   ctx = LLM::Context.new(llm)
  #   ctx.talk "Hello"
  #   ctx.messages.select(&:assistant?).each { print "[#{_1.role}]", _1.content, "\n" }
  class DeepInfra < OpenAI
    HOST = "api.deepinfra.com"
    BASE_PATH = "/v1/openai"

    ##
    # @param key (see LLM::Provider#initialize)
    # @param host (see LLM::Provider#initialize)
    # @param base_path (see LLM::Provider#initialize)
    # @return [LLM::DeepInfra]
    def initialize(host: HOST, base_path: BASE_PATH, **)
      super
    end

    ##
    # @return [Symbol]
    #  Returns the provider's name
    def name
      :deepinfra
    end

    ##
    # Provides an interface to DeepInfra's OpenAI-compatible image API.
    # @see https://deepinfra.com/models/text-to-image DeepInfra image models
    # @return [LLM::OpenAI::Images]
    def images
      super
    end

    ##
    # Provides an embedding.
    # @see https://deepinfra.com/BAAI/bge-m3 BAAI/bge-m3
    # @param input (see LLM::Provider#embed)
    # @param model (see LLM::Provider#embed)
    # @param params (see LLM::Provider#embed)
    # @raise (see LLM::Provider#request)
    # @return (see LLM::Provider#embed)
    def embed(input, model: "BAAI/bge-m3", **params)
      super
    end

    ##
    # @raise [NotImplementedError]
    def responses
      raise NotImplementedError
    end

    ##
    # @raise [NotImplementedError]
    def audio
      raise NotImplementedError
    end

    ##
    # @raise [NotImplementedError]
    def files
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
    # @see https://deepinfra.com/models/zai-org/GLM-5.2 zai-org/GLM-5.2
    # @return [String]
    def default_model
      "zai-org/GLM-5.2"
    end
  end
end
