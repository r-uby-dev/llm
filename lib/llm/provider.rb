# frozen_string_literal: true

##
# The Provider class is the abstract base for LLM service integrations.
# Most users interact with providers through {LLM::Agent} or
# {LLM::Context} rather than calling {#complete} directly.
#
# @abstract
class LLM::Provider
  include LLM::Transport::Execution

  ##
  # @param [String, nil] key
  #  The secret key for authentication
  # @param [String] host
  #  The host address of the LLM provider
  # @param [Integer] port
  #  The port number
  # @param [Integer] timeout
  #  The number of seconds to wait for a response. Also serves as the
  #  default read timeout.
  # @param [Integer, nil] read_timeout
  #  The number of seconds to wait for a response. Defaults to `timeout`.
  # @param [Integer] connect_timeout
  #  The number of seconds to wait for a TCP connection to open.
  # @param [Boolean] ssl
  #  Whether to use SSL for the connection
  # @param [String] base_path
  #  Optional base path prefix for HTTP API routes.
  # @param [Boolean] persistent
  #  Whether to use a persistent connection.
  #  Requires the net-http-persistent gem.
  # @param [LLM::Transport, Class, nil] transport
  #  Optional override with any {LLM::Transport} instance or subclass.
  def initialize(key:, host:, port: 443, timeout: 600, read_timeout: nil, connect_timeout: 5, ssl: true, base_path: "", persistent: false, transport: nil)
    @key = key
    @host = host
    @port = port
    @read_timeout = read_timeout || timeout
    @timeout = @read_timeout
    @connect_timeout = connect_timeout
    @ssl = ssl
    @base_path = LLM::Utils.normalize_base_path(base_path)
    @base_uri = URI("#{ssl ? "https" : "http"}://#{host}:#{port}/")
    @headers = {"User-Agent" => "llm.rb v#{LLM::VERSION}"}
    @monitor = Monitor.new
    @transport = LLM::Transport::Utils.resolve_transport(
      host:,
      port:,
      timeout: @read_timeout,
      connect_timeout: @connect_timeout,
      ssl:,
      transport:,
      persistent:
    )
  end

  ##
  # Builds the outgoing message array for a turn. Normalizes the
  # prompt into one or more {LLM::Message} objects and prepends
  # the existing history.
  #
  # The method is idempotent. If the prompt is already an
  # {LLM::Message} or an array of {LLM::Message}s (ie it was built
  # by a previous call and possibly transformed), it is returned
  # as-is without rebuilding.
  #
  # @param [String, Array, LLM::Message, LLM::Prompt] prompt
  # @param [Hash] params
  #  Turn params. The history is taken from `params[:messages]`.
  # @param [Symbol] role
  #  The role to assign to a raw prompt
  # @param [Symbol] key
  #  The params key that holds the history (`:messages` for chat
  #  completions, `:input` for the responses API).
  # @return [Array<LLM::Message>]
  def build_messages(prompt, params, role, key: :messages)
    case prompt
    when LLM::Message
      [prompt]
    when Array
      if prompt.all? { LLM::Message === _1 }
        prompt
      else
        [*(params.delete(key) || []), LLM::Message.new(role, prompt)]
      end
    when LLM::Prompt
      [*(params.delete(key) || []), *prompt.to_a]
    else
      [*(params.delete(key) || []), LLM::Message.new(role, prompt)]
    end
  end

  ##
  # Returns an inspection of the provider object
  # @return [String]
  # @note The secret key is redacted in inspect for security reasons
  def inspect
    "#<#{LLM::Utils.object_id(self)} @key=[REDACTED] @transport=#{transport.inspect} @tracer=#{tracer.inspect}>"
  end

  ##
  # @raise [NotImplementedError]
  #  When the method is not implemented by a subclass
  # @return [Symbol]
  #  Returns the provider's name
  def name
    raise NotImplementedError
  end

  ##
  # Returns the provider's model registry.
  # @return [LLM::Registry]
  def registry
    LLM.registry_for(self)
  end

  ##
  # Provides an embedding
  # @param [String, Array<String>] input
  #  The input to embed
  # @param [String] model
  #  The embedding model to use
  # @param [Hash] params
  #  Other embedding parameters
  # @raise [NotImplementedError]
  #  When the method is not implemented by a subclass
  # @return [LLM::Response]
  def embed(input, model: nil, **params)
    raise NotImplementedError
  end

  ##
  # @note
  #  This feature is not implemented by all providers,
  #  and it will raise NotImplementedError for providers
  #  that do not support it.
  # @return [LLM::Response]
  def ocr(...)
    raise NotImplementedError
  end

  ##
  # Provides an interface to the chat completions API.
  # Most users should use {LLM::Context#talk} or {LLM::Agent#talk} instead.
  #
  # @example
  #   llm = LLM.openai(key: ENV["KEY"])
  #   messages = [{role: "system", content: "Your task is to answer all of my questions"}]
  #   res = llm.complete("5 + 2 ?", messages:)
  #   print "[#{res.messages[0].role}]", res.messages[0].content, "\n"
  # @param [String] prompt
  #  The input prompt to be completed
  # @param [Hash] params
  #  The parameters to maintain throughout the conversation.
  #  Any parameter the provider supports can be included and
  #  not only those listed here.
  # @option params [Symbol] :role Defaults to the provider's default role
  # @option params [String] :model Defaults to the provider's default model
  # @option params [#to_json, nil] :schema Defaults to nil
  # @option params [Array<LLM::Function>, nil] :tools Defaults to nil
  # @raise [NotImplementedError]
  #  When the method is not implemented by a subclass
  # @return [LLM::Response]
  def complete(prompt, params = {})
    raise NotImplementedError
  end

  ##
  # Starts a new chat powered by the chat completions API
  # @param prompt (see LLM::Provider#complete)
  # @param params (see LLM::Provider#complete)
  # @return [LLM::Context]
  def chat(prompt, params = {})
    role = params.delete(:role)
    LLM::Context.new(self, params).talk(prompt, role:)
  end

  ##
  # Starts a new chat powered by the responses API
  # @param prompt (see LLM::Provider#complete)
  # @param params (see LLM::Provider#complete)
  # @raise (see LLM::Provider#complete)
  # @return [LLM::Context]
  def respond(prompt, params = {})
    role = params.delete(:role)
    LLM::Context.new(self, params).respond(prompt, role:)
  end

  ##
  # @note
  # Compared to the chat completions API, the responses API
  # can require less bandwidth on each turn, maintain state
  # server-side, and produce faster responses.
  # @return [LLM::OpenAI::Responses]
  #  Returns an interface to the responses API
  def responses
    raise NotImplementedError
  end

  ##
  # @return [LLM::OpenAI::Images, LLM::Google::Images]
  #  Returns an interface to the images API
  def images
    raise NotImplementedError
  end

  ##
  # @return [LLM::OpenAI::Audio]
  #  Returns an interface to the audio API
  def audio
    raise NotImplementedError
  end

  ##
  # @return [LLM::OpenAI::Files]
  #  Returns an interface to the files API
  def files
    raise NotImplementedError
  end

  ##
  # @return [LLM::OpenAI::Models]
  #  Returns an interface to the models API
  def models
    raise NotImplementedError
  end

  ##
  # @return [LLM::OpenAI::Moderations]
  #  Returns an interface to the moderations API
  def moderations
    raise NotImplementedError
  end

  ##
  # @return [LLM::OpenAI::VectorStore]
  #  Returns an interface to the vector stores API
  def vector_stores
    raise NotImplementedError
  end

  ##
  # @return [String]
  #  Returns the role of the assistant in the conversation.
  #  Usually "assistant" or "model"
  def assistant_role
    raise NotImplementedError
  end

  ##
  # @return [String]
  #  Returns the default model for chat completions
  def default_model
    raise NotImplementedError
  end

  ##
  # Returns the number of times a rate-limited
  # request is retried before the error is raised.
  #
  # Each retry sleeps a growing interval, so a budget
  # that is exhausted surfaces the rate-limit error
  # instead of blocking indefinitely. A provider can
  # return a different budget when its API recovers
  # from rate limits more slowly.
  #
  # @see LLM::Agent#retry_budget
  # @return [Integer]
  def retry_budget
    5
  end

  ##
  # Returns an object that can generate a JSON schema
  # @return [LLM::Schema]
  def schema
    LLM::Schema.new
  end

  ##
  # Add one or more headers to all requests, or scope them to a block.
  #
  # Without a block the headers are merged into the provider's defaults
  # permanently. With a block the headers apply only to the current fiber,
  # for the duration of the block, then the previous headers are restored.
  # This is useful for a header that varies per context, such as
  # OpenRouter's `x-session-id`.
  # @example Permanent
  #   llm = LLM.openai(key: ENV["KEY"])
  #   llm.with("OpenAI-Organization" => ENV["ORG"])
  #   llm.with("OpenAI-Project" => ENV["PROJECT"])
  # @example Scoped
  #   llm.with("x-session-id" => ctx.id) do
  #     llm.complete("hello")
  #   end
  # @param [Hash<String,String>] headers
  #  One or more headers
  # @note
  #  For backwards compatibility, headers can be
  #  provided via the `headers:` keyword argument,
  #  or provided directly as a Hash without the
  #  `headers:` key namespace.
  # @yield
  # @return [LLM::Provider]
  #  Returns self without a block, the block's value with one
  def with(**headers, &block)
    headers = headers.merge(headers.delete(:headers) || {})
    if block
      wm = weakmaps.header
      previous = wm[self]
      wm[self] = (previous || {}).merge(headers)
      block.call
    else
      lock { tap { @headers.merge!(headers) } }
    end
  ensure
    if block
      if previous.nil?
        wm.respond_to?(:delete) ? wm.delete(self) : wm[self] = nil
      else
        wm[self] = previous
      end
    end
  end

  ##
  # @note
  #  This method might be outdated, and the {LLM::Provider#server_tool LLM::Provider#server_tool}
  #  method can be used if a tool is not found here.
  # Returns all known tools provided by a provider.
  # @return [String => LLM::ServerTool]
  def server_tools
    {}
  end

  ##
  # @note
  #   OpenAI, Anthropic, and Gemini provide platform-tools for things
  #   like web search, and more.
  # Returns a tool provided by a provider.
  # @example
  #   llm   = LLM.openai(key: ENV["KEY"])
  #   tools = [llm.server_tool(:web_search)]
  #   res   = llm.responses.create("Summarize today's news", tools:)
  #   print res.output_text, "\n"
  # @param [String, Symbol] name The name of the tool
  # @param [Hash] options Configuration options for the tool
  # @return [LLM::ServerTool]
  def server_tool(name, options = {})
    LLM::ServerTool.new(name, options, self)
  end

  ##
  # Provides a web search capability
  # @param [String] query The search query
  # @raise [NotImplementedError]
  #  When the method is not implemented by a subclass
  # @return [LLM::Response]
  def web_search(query:)
    raise NotImplementedError
  end

  ##
  # @return [Symbol]
  def user_role
    :user
  end

  ##
  # @return [Symbol]
  def system_role
    :system
  end

  ##
  # @return [Symbol]
  def developer_role
    :developer
  end

  ##
  # @return [Symbol]
  def tool_role
    :tool
  end

  ##
  # @return [LLM::Tracer]
  #  Returns the current scoped tracer override or provider default tracer
  def tracer
    weakmaps.tracer[self] || @tracer || LLM::Tracer::Null.new(self)
  end

  ##
  # Set the provider's default tracer
  # This tracer is shared by the provider instance and becomes the fallback
  # whenever no scoped override is active.
  #
  # A tracer assigned this way is not scoped, so nothing declares when it
  # is finished and {LLM::Tracer#on_exit} never fires for it. Release what
  # it holds when the provider is done with, or scope it with
  # {#with_tracer} instead.
  #
  # @example
  #   llm = LLM.openai(key: ENV["KEY"])
  #   llm.tracer = LLM::Tracer.logger(llm, path: "/path/to/log.txt")
  #   llm.with_tracer(llm.tracer) do
  #     # ...
  #   end
  # @param [LLM::Tracer] tracer
  #  A tracer
  # @return [void]
  def tracer=(tracer)
    @tracer = tracer || LLM::Tracer::Null.new(self)
  end

  ##
  # Override the tracer for the current fiber while the block runs.
  # This is useful when you want per-request or per-turn tracing without
  # replacing the provider's default tracer.
  # @example
  #   llm.with_tracer(LLM::Tracer.logger(llm, io: $stdout)) do
  #     llm.complete("hello", model: "gpt-5.4-mini")
  #   end
  # @param [LLM::Tracer] tracer
  # @yield
  # @return [Object]
  def with_tracer(tracer)
    scoped = tracer || LLM::Tracer::Null.new(self)
    wm = weakmaps.tracer
    had_override = wm.key?(self)
    previous = wm[self]
    wm[self] = scoped
    entered = LLM::Tracer.enter(scoped)
    yield
  ensure
    if had_override
      wm[self] = previous
    else
      wm.respond_to?(:delete) ? wm.delete(self) : wm[self] = nil
    end
    ##
    # The scope this tracer was opened for is over, and the tracer is
    # told so when the last one that is open for it ends - on whichever
    # thread that happens, because a tool opens a scope of its own for
    # the turn's tracer.
    LLM::Tracer.exit(scoped) if entered
  end

  ##
  # Interrupt the active request, if any.
  # @param [Fiber] owner
  # @return [nil]
  def interrupt!(owner)
    transport.interrupt!(owner)
  end
  alias_method :cancel!, :interrupt!

  ##
  # Returns the current request owner used by the transport.
  # @return [Object]
  # @api private
  def request_owner
    transport.request_owner
  end

  ##
  # @return [Boolean]
  #  Returns true when an API key is configured
  def key?
    @key != nil && @key.to_s.strip.size > 0
  end

  ##
  # Adapt a {LLM::Function} to the provider-specific tool schema.
  # @abstract
  # @param [LLM::Function] fn
  # @raise [NotImplementedError]
  # @return [Hash]
  def adapt_function(fn)
    raise NotImplementedError
  end

  private

  def path(suffix, base_path: true)
    return suffix if !base_path || @base_path.empty?
    "#{@base_path}#{suffix}"
  end

  attr_reader :base_uri, :host, :port, :timeout, :read_timeout, :connect_timeout, :ssl, :transport

  ##
  # The headers to include with a request
  # @raise [NotImplementedError]
  #  (see LLM::Provider#complete)
  def headers
    raise NotImplementedError
  end

  ##
  # @return [Class]
  #  Returns the class responsible for handling an unsuccessful LLM response
  # @raise [NotImplementedError]
  #  (see LLM::Provider#complete)
  def error_handler
    raise NotImplementedError
  end

  ##
  # @return [Class]
  def event_handler
    LLM::EventHandler
  end

  ##
  # @return [Class]
  #  Returns the provider-specific Server-Side Events (SSE) parser
  def stream_parser
    raise NotImplementedError
  end

  ##
  # @return [Class]
  #  Returns the class responsible for decoding streamed response bodies
  def stream_decoder
    LLM::Transport::StreamDecoder
  end

  ##
  # Resolves tools to their function representations
  # @param [Array<LLM::Function, LLM::Tool>] tools
  #  The tools to map
  # @raise [TypeError]
  #  When a tool is not recognized
  # @return [Array<LLM::Function>]
  def resolve_tools(tools)
    (tools || []).map do |tool|
      if tool.respond_to?(:function)
        tool.function
      elsif [LLM::Function, LLM::ServerTool, Hash].any? { _1 === tool }
        tool
      else
        raise TypeError, "#{tool.class} given as a tool but it is not recognized"
      end
    end
  end

  ##
  # @api private
  def lock(&)
    @monitor.synchronize(&)
  end

  ##
  # @api private
  def thread
    Thread.current
  end

  ##
  # Returns the temporary headers set by {#with}
  # for the current fiber.
  # @api private
  # @return [Hash]
  def temporary_headers
    weakmaps.header[self] || {}
  end

  ##
  # @return [LLM::Object]
  def weakmaps
    if thread["llm.#{name}.weakmaps"]
      thread["llm.#{name}.weakmaps"]
    else
      weakmaps = LLM::Object.from(
        tracer: ObjectSpace::WeakMap.new,
        header: ObjectSpace::WeakKeyMap.new
      )
      thread["llm.#{name}.weakmaps"] = weakmaps
    end
  end
end
