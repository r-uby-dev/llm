# frozen_string_literal: true

require_relative "openai" unless defined?(LLM::OpenAI)

module LLM
  ##
  # The Hanzo class implements a provider for
  # [hanzo.ai](https://hanzo.ai).
  class Hanzo < OpenAI
    def initialize(host: "api.hanzo.ai", port: 443, ssl: true, **)
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
    # @see https://api-docs.deepseek.com/quick_start/pricing deepseek-v4-flash
    # @return [String]
    def default_model
      "enso-auto"
    end
  end
end
