# frozen_string_literal: true

module LLM
  ##
  # The Google class implements a provider for
  # [Gemini](https://ai.google.dev/). The Google provider
  # can accept multiple inputs (text, images, audio, and video).
  # The inputs can be provided inline via the prompt for files
  # under 20MB or via the Gemini Files API for files
  # that are over 20MB.
  #
  # @example
  #   #!/usr/bin/env ruby
  #   require "llm"
  #
  #   llm = LLM.google(key: ENV["KEY"])
  #   ctx = LLM::Context.new(llm)
  #   ctx.talk ["Tell me about this photo", ctx.local_file("/images/photo.png")]
  #   ctx.messages.select(&:assistant?).each { print "[#{_1.role}]", _1.content, "\n" }
  class Google < Provider
    require_relative "google/utils"
    require_relative "google/error_handler"
    require_relative "google/request_adapter"
    require_relative "google/response_adapter"
    require_relative "google/stream_parser"
    require_relative "google/models"
    require_relative "google/images"
    require_relative "google/audio"
    require_relative "google/files"

    include RequestAdapter
    extend Utils

    HOST = "generativelanguage.googleapis.com"

    ##
    # @param key (see LLM::Provider#initialize)
    def initialize(**)
      super(host: HOST, **)
    end

    ##
    # @return [Symbol]
    #  Returns the provider's name
    def name
      :google
    end

    ##
    # Provides an embedding
    # @param input (see LLM::Provider#embed)
    # @param model (see LLM::Provider#embed)
    # @param params (see LLM::Provider#embed)
    # @raise (see LLM::Provider#request)
    # @return [LLM::Response]
    def embed(input, model: "gemini-embedding-001", **params)
      model = model.respond_to?(:id) ? model.id : model
      path = ["/v1beta/models/#{model}", "embedContent?key=#{@key}"].join(":")
      req = LLM::Transport::Request.post(path, headers)
      req.body = LLM.json.dump({content: {parts: [{text: input}]}})
      res, span, tracer = execute(request: req, operation: "embeddings", model:)
      res = ResponseAdapter.adapt(res, type: :embedding)
      tracer.on_request_finish(operation: "embeddings", model:, res:, span:)
      res
    end

    ##
    # Provides an interface to the chat completions API
    # @see https://ai.google.dev/api/generate-content#v1beta.models.generateContent Gemini docs
    # @param prompt (see LLM::Provider#complete)
    # @param params (see LLM::Provider#complete)
    # @example (see LLM::Provider#complete)
    # @raise (see LLM::Provider#request)
    # @raise [LLM::PromptError]
    #  When given an object a provider does not understand
    # @return [LLM::Response]
    def complete(prompt, params = {})
      params, stream, tools, role, model = normalize_complete_params(params)
      req = build_complete_request(prompt, params, role, model, stream)
      res, span, tracer = execute(request: req, stream: stream, operation: "chat", model:)
      res = ResponseAdapter.adapt(res, type: :completion)
        .extend(Module.new { define_method(:__tools__) { tools } })
      tracer.on_request_finish(operation: "chat", model:, res:, span:)
      res
    end

    ##
    # Provides an interface to Gemini's audio API
    # @see https://ai.google.dev/gemini-api/docs/audio Gemini docs
    # @return [LLM::Google::Audio]
    def audio
      LLM::Google::Audio.new(self)
    end

    ##
    # Provides an interface to Gemini's image generation API
    # @see https://ai.google.dev/gemini-api/docs/image-generation Gemini docs
    # @return [see LLM::Google::Images]
    def images
      LLM::Google::Images.new(self)
    end

    ##
    # Provides an interface to Gemini's file management API
    # @see https://ai.google.dev/gemini-api/docs/files Gemini docs
    # @return [LLM::Google::Files]
    def files
      LLM::Google::Files.new(self)
    end

    ##
    # Provides an interface to Gemini's models API
    # @see https://ai.google.dev/gemini-api/docs/models Gemini docs
    # @return [LLM::Google::Models]
    def models
      LLM::Google::Models.new(self)
    end

    ##
    # Returns the default model for chat completions
    # @see https://ai.google.dev/gemini-api/docs/models#gemini-31-flash-lite gemini-3.1-flash-lite
    # @return [String]
    def default_model
      "gemini-3.1-flash-lite"
    end

    ##
    # @note
    #  This method includes certain tools that require configuration
    #  through a set of options that are easier to set through the
    #  {LLM::Provider#server_tool LLM::Provider#server_tool} method.
    # @see https://ai.google.dev/gemini-api/docs/google-search Gemini docs
    # @return (see LLM::Provider#server_tools)
    def server_tools
      {
        google_search: server_tool(:google_search),
        code_execution: server_tool(:code_execution),
        url_context: server_tool(:url_context)
      }
    end

    ##
    # A convenience method for performing a web search using the
    # Google Search tool.
    # @param query [String] The search query.
    # @return [LLM::Response] The response from the LLM provider.
    def web_search(query:)
      ResponseAdapter.adapt(complete(query, tools: [server_tools[:google_search]]), type: :web_search)
    end

    ##
    # @return [Symbol]
    #  Returns the providers user role
    def user_role
      :user
    end

    ##
    # @return [Symbol]
    #  Returns the providers system role
    def system_role
      :user
    end

    ##
    # @return [Symbol]
    # Returns the providers developer role
    def developer_role
      :user
    end

    ##
    # @return (see LLM::Provider#assistant_role)
    def assistant_role
      "model"
    end

    private

    def headers
      lock do
        (@headers || {}).merge(
          "Content-Type" => "application/json"
        )
      end
    end

    def stream_parser
      LLM::Google::StreamParser
    end

    def error_handler
      LLM::Google::ErrorHandler
    end

    def normalize_complete_params(params)
      params = {role: :user, model: default_model}.merge!(params)
      tools  = resolve_tools(params.delete(:tools))
      params = [params, adapt_schema(params), adapt_tools(tools)].inject({}, &:merge!).compact
      role, model, stream = [:role, :model, :stream].map { params.delete(_1) }
      [params, stream, tools, role, model]
    end

    def build_complete_request(prompt, params, role, model, stream)
      action = stream ? "streamGenerateContent?key=#{@key}&alt=sse" : "generateContent?key=#{@key}"
      model.respond_to?(:id) ? model.id : model
      path = ["/v1beta/models/#{model}", action].join(":")
      req  = LLM::Transport::Request.post(path, headers)
      messages = build_complete_messages(prompt, params, role)
      body = LLM.json.dump({contents: adapt(messages)}.merge!(params))
      transport.set_body_stream(req, StringIO.new(body))
      req
    end

    def build_complete_messages(prompt, params, role)
      if LLM::Prompt === prompt
        [*(params.delete(:messages) || []), *prompt.to_a]
      else
        [*(params.delete(:messages) || []), LLM::Message.new(role, prompt)]
      end
    end
  end
end
