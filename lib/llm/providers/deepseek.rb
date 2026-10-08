# frozen_string_literal: true

require_relative "openai" unless defined?(LLM::OpenAI)

module LLM
  ##
  # The DeepSeek class implements a provider for
  # [DeepSeek](https://deepseek.com)
  # through its OpenAI-compatible API available via
  # their [web platform](https://platform.deepseek.com).
  #
  # @example
  #   #!/usr/bin/env ruby
  #   require "llm"
  #
  #   llm = LLM.deepseek(key: ENV["KEY"])
  #   ctx = LLM::Context.new(llm)
  #   ctx.talk "Hello"
  #   ctx.messages.select(&:assistant?).each { print "[#{_1.role}]", _1.content, "\n" }
  class DeepSeek < OpenAI
    require_relative "deepseek/request_adapter"
    require_relative "deepseek/response_adapter"
    require_relative "deepseek/files"
    require_relative "deepseek/images"
    include DeepSeek::RequestAdapter

    ##
    # @param (see LLM::Provider#initialize)
    # @return [LLM::DeepSeek]
    def initialize(host: "api.deepseek.com", port: 443, ssl: true, **)
      super
    end

    ##
    # @return [Symbol]
    #  Returns the provider's name
    def name
      :deepseek
    end

    ##
    # Provides an interface to DeepSeek's files API
    # @see https://api-docs.deepseek.com/guides/files_api DeepSeek docs
    # @return [LLM::DeepSeek::Files]
    def files
      LLM::DeepSeek::Files.new(self)
    end

    ##
    # @raise [LLM::DeepSeek::Images]
    def images
      LLM::DeepSeek::Images.new(self)
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
      "deepseek-flash"
    end
  end
end
