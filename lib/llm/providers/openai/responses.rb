# frozen_string_literal: true

class LLM::OpenAI
  ##
  # The {LLM::OpenAI::Responses LLM::OpenAI::Responses} class provides
  # an interface for [OpenAI's response API](https://platform.openai.com/docs/guides/conversation-state?api-mode=responses).
  #
  # @example example #1
  #   #!/usr/bin/env ruby
  #   require "llm"
  #
  #   llm = LLM.openai(key: ENV["KEY"])
  #   res1 = llm.responses.create "Your task is to answer the user's questions", role: :developer
  #   res2 = llm.responses.create "5 + 5 = X ?", role: :user, previous_response_id: res1.id
  #   [res1, res2].each { llm.responses.delete(_1) }
  class Responses
    require_relative "responses/stream_parser"
    include RequestAdapter

    ##
    # Returns a new Responses object
    # @param provider [LLM::Provider]
    # @return [LLM::OpenAI::Responses]
    def initialize(provider)
      @provider = provider
    end

    ##
    # Create a response
    # @see https://platform.openai.com/docs/api-reference/responses/create OpenAI docs
    # @param prompt (see LLM::Provider#complete)
    # @param params (see LLM::Provider#complete)
    # @raise (see LLM::Provider#request)
    # @raise [LLM::PromptError]
    #  When given an object a provider does not understand
    # @return [LLM::Response]
    def create(prompt, params = {})
      params = {role: :user, model: @provider.default_model}.merge!(params)
      tools  = resolve_tools(params.delete(:tools))
      params = [params, adapt_schema(params), adapt_tools(tools)].inject({}, &:merge!).compact
      role, stream = params.delete(:role), params.delete(:stream)
      params[:stream] = true if @provider.streamable?(stream) || stream == true
      req = LLM::Transport::Request.post(path("/responses"), headers)
      messages = build_complete_messages(prompt, params, role)
      @provider.tracer.set_request_metadata(user_input: extract_user_input(messages, fallback: prompt))
      body = LLM.json.dump({input: [adapt(messages, mode: :response)].flatten}.merge!(params))
      transport.set_body_stream(req, StringIO.new(body))
      res, span, tracer = execute(request: req, stream:, stream_parser:, operation: "chat", model: params[:model])
      res = ResponseAdapter.adapt(res, type: :responds)
        .extend(Module.new { define_method(:__tools__) { tools } })
      tracer.on_request_finish(operation: "chat", model: params[:model], res:, span:)
      res
    end

    ##
    # Get a response
    # @see https://platform.openai.com/docs/api-reference/responses/get OpenAI docs
    # @param [#id, #to_s] response Response ID
    # @raise (see LLM::Provider#request)
    # @return [LLM::Response]
    def get(response, **params)
      response_id = response.respond_to?(:id) ? response.id : response
      query = URI.encode_www_form(params)
      req = LLM::Transport::Request.get(path("/responses/#{response_id}?#{query}"), headers)
      res, span, tracer = execute(request: req, operation: "request")
      res = ResponseAdapter.adapt(res, type: :responds)
      tracer.on_request_finish(operation: "request", res:, span:)
      res
    end

    ##
    # Deletes a response
    # @see https://platform.openai.com/docs/api-reference/responses/delete OpenAI docs
    # @param [#id, #to_s] response Response ID
    # @raise (see LLM::Provider#request)
    # @return [LLM::Object] Response body
    def delete(response)
      response_id = response.respond_to?(:id) ? response.id : response
      req = LLM::Transport::Request.delete(path("/responses/#{response_id}"), headers)
      res, span, tracer = execute(request: req, operation: "request")
      res = LLM::Response.new(res)
      tracer.on_request_finish(operation: "request", res:, span:)
      res
    end

    private

    [:path, :headers, :execute, :transport, :resolve_tools].each do |m|
      define_method(m) { |*args, **kwargs, &b| @provider.send(m, *args, **kwargs, &b) }
    end

    def build_complete_messages(prompt, params, role)
      if LLM::Prompt === prompt
        [*(params.delete(:input) || []), *prompt]
      else
        [*(params.delete(:input) || []), LLM::Message.new(role, prompt)]
      end
    end

    def adapt_schema(params)
      return {} unless params && params[:schema]
      schema = params.delete(:schema)
      schema = schema.respond_to?(:object) ? schema.object : schema
      schema = schema.to_h.merge(additionalProperties: false)
      name = "JSONSchema"
      {text: {format: {type: "json_schema", name:, schema:}}}
    end

    def stream_parser
      LLM::OpenAI::Responses::StreamParser
    end

    def extract_user_input(messages, fallback:)
      message = messages.reverse.find(&:user?) || messages.last
      value = message&.content || fallback
      value.is_a?(String) ? value : LLM.json.dump(value)
    end
  end
end
