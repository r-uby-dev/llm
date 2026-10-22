# frozen_string_literal: true

require_relative "openai" unless defined?(LLM::OpenAI)

module LLM
  ##
  # The Hanzo class implements a provider for
  # [hanzo.ai](https://hanzo.ai) through its
  # OpenAI-compatible chat completions API.
  #
  # @example
  #   #!/usr/bin/env ruby
  #   require "llm"
  #
  #   llm   = LLM.hanzo
  #   agent = LLM::Agent.new(llm)
  #   agent.talk "hello world", stream: $stdout
  class Hanzo < OpenAI
    HOST = "api.hanzo.ai"
    BASE_PATH = "/v1"

    ##
    # @param key (see LLM::Provider#initialize)
    # @param host (see LLM::Provider#initialize)
    # @param base_path (see LLM::Provider#initialize)
    # @return [LLM::Hanzo]
    def initialize(host: HOST, base_path: BASE_PATH, port: 443, ssl: true, **)
      super
    end

    ##
    # Returns the provider's name
    # @return [Symbol]
    def name
      :hanzo
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
    def responses
      raise NotImplementedError
    end

    ##
    # @raise [NotImplementedError]
    def vector_stores
      raise NotImplementedError
    end

    ##
    # Returns the default model for chat completions
    # @note
    #  The default is routed automatically by Hanzo.
    #  Without a paid plan, it defaults to enso-free.
    # @see https://platform.hanzo.ai/models enso-auto
    # @return [String]
    def default_model
      "enso-auto"
    end
  end
end
