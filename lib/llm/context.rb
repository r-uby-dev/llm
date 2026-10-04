# frozen_string_literal: true

module LLM
  ##
  # {LLM::Context LLM::Context} is the low-level stateful execution
  # boundary in llm.rb. Most users should start with {LLM::Agent}, which
  # wraps Context and manages tool loops automatically. Use Context
  # directly when you need manual control over tool execution.
  #
  # It holds the evolving runtime state for an LLM workflow:
  # conversation history, tool calls and returns, schema and streaming
  # configuration, accumulated usage, and request ownership for
  # interruption.
  #
  # This is broader than prompt context alone. A context is the object
  # that lets one-off prompts, streaming turns, tool execution,
  # persistence, retries, and serialized long-lived workflows all run
  # through the same model.
  #
  # A context can drive the chat completions API that all providers
  # support or the Responses API on providers that expose it.
  #
  # @example
  #   #!/usr/bin/env ruby
  #   require "llm"
  #
  #   llm = LLM.deepseek(key: ENV["KEY"])
  #   ctx = LLM::Context.new(llm, stream: $stdout)
  #   ctx.talk "If a train goes 60 mph for 1.5 hours, how far does it travel?"
  #   ctx.messages.each { |m| puts "[#{m.role}] #{m.content}" }
  #
  # @see LLM::Agent The recommended high-level interface
  # @see LLM::Buffer Message history (ctx.messages)
  # @see LLM::Message Individual messages in the conversation
  # @see LLM::Response Response returned by each turn
  class Context
    require_relative "context/serializer"
    require_relative "context/deserializer"
    include Serializer
    include Deserializer

    TRY_ERRORS = [
      "LLM::InsufficientQuotaError",
      "LLM::RateLimitError",
      "Net::ReadTimeout",
      "Net::WriteTimeout",
      "Net::OpenTimeout"
    ]
    private_constant :TRY_ERRORS

    ##
    # Returns the set of runtime parameters that
    # configure this context and must never be forwarded
    # to a provider request body.
    # @api private
    # @return [Array<Symbol>]
    def self.params
      %w[guard retry_budget concurrency transformer compactor record id]
    end

    ##
    # Returns the accumulated message history for this context
    # @return [LLM::Buffer<LLM::Message>]
    attr_reader :messages

    ##
    # Returns a provider
    # @return [LLM::Provider]
    attr_reader :llm

    ##
    # Returns the context mode
    # @return [Symbol]
    attr_reader :mode

    ##
    # Returns the ORM record this context is bound to, or nil.
    # @return [Object, nil]
    attr_reader :record

    ##
    # Returns a stable id for this context. It is generated once
    # on creation and restored with the runtime state on load - and a
    # context bound to a record takes the record's id instead, when that
    # id is a UUIDv7 string.
    # @return [String]
    attr_reader :id

    ##
    # @param [LLM::Provider] llm
    #  A provider
    # @param [Hash] params
    #  The parameters to maintain throughout the conversation.
    #  Any parameter the provider supports can be included and
    #  not only those listed here.
    # @option params [Symbol] :mode
    #   Defaults to `:responses` for OpenAI, otherwise it defaults
    #   to `:completions`.
    # @option params [String] :model Defaults to the provider's default model
    # @option params [String] :id
    #   A stable id for the context. Defaults to the record's id when the
    #   context is bound to a record whose id is a UUIDv7, and to a
    #   generated UUIDv7 otherwise. A UUIDv7 is recommended - it is what
    #   makes `created_at` answerable - but not required: any value is
    #   stored and restored as given.
    # @option params [Class<LLM::Compactor>, nil] :compactor
    #   A compactor class to use for context compaction. Defaults to
    #   {LLM::Compactor::Null}.
    # @option params [Hash] :compactor_options
    #   Options passed to the compactor's `call` method. Defaults to `{}`.
    # @option params [Class<LLM::Transformer>, nil] :transformer
    #   A transformer class to use for message transformation. Defaults to
    #   {LLM::Transformer::Null}.
    # @option params [Hash] :transformer_options
    #   Options passed to the transformer's `call` method. Defaults to `{}`.
    # @option params [Class<LLM::Guard>, nil] :guard
    #   A guard class to supervise agentic tool execution. Defaults to
    #   {LLM::Guard::Null}.
    # @option params [Hash] :guard_options
    #   Options passed to the guard's `call` method. Defaults to `{}`.
    # @option params [Array<LLM::Function>, nil] :tools Defaults to nil
    # @option params [Array<String>, nil] :skills Defaults to nil
    def initialize(llm, params = {})
      params = {}.merge!(params)
      @llm = llm
      @record = params.delete(:record)
      @id = params.delete(:id) || makeid
      @mode = params.delete(:mode) || (llm.name == :openai ? :responses : :completions)
      tools = [*params.delete(:tools), *load_skills(params.delete(:skills))]
      @params = {model: llm.default_model, schema: nil}.compact.merge!(params)
      @params[:tools] = tools unless tools.empty?
      @params[:store] ||= false if @mode == :responses
      @messages = LLM::Buffer.new(llm)
      extra = @params.slice(:model, :tools).merge!(ctx: self, tracer:)
      @params[:stream] = LLM::Stream.try(@params[:stream], extra:)
      @compactor = {
        klass: params.delete(:compactor) || LLM::Compactor::Null,
        options: params.delete(:compactor_options) || {}
      }
      @transformer = {
        klass: params.delete(:transformer) || LLM::Transformer::Null,
        options: params.delete(:transformer_options) || {}
      }
      @guard = {
        klass: params.delete(:guard) || LLM::Guard::Null,
        options: params.delete(:guard_options) || {}
      }
      @retry_budget = params.delete(:retry_budget) || 0
    end

    ##
    # Returns the retry budget for rate-limited requests.
    # @return [Integer]
    def retry_budget
      @retry_budget
    end

    ##
    # Returns the default params for this context
    # @return [Hash]
    def params
      @params.dup
    end

    ##
    # Returns a context compactor
    # @return [LLM::Compactor]
    def compactor
      @compactor[:klass]
    end

    ##
    # Returns whether the context has been compacted and no later model
    # response has cleared that state.
    # @return [Boolean]
    # @api private
    attr_accessor :compacted
    alias_method :compacted?, :compacted

    ##
    # Returns the configured guard class.
    #
    # Guards are context-level supervisors for agentic execution. A guard can
    # inspect the runtime state and decide whether pending tool work should be
    # blocked before the context keeps looping.
    #
    # The guard is stamped onto the functions the context binds, so it runs
    # whenever a task is spawned — including tool calls queued from a stream
    # via {LLM::Stream#on_tool_call}. A blocked call yields its in-band
    # `guard_error` return without executing.
    #
    # @return [Class<LLM::Guard>]
    def guard
      @guard[:klass]
    end

    ##
    # Returns the configured transformer class.
    #
    # Transformers rewrite the most recent message before it is sent to the
    # provider.
    #
    # @return [Class<LLM::Transformer>]
    def transformer
      @transformer[:klass]
    end

    # Interact with the context via the chat completions API.
    # This method immediately sends a request to the LLM and returns the response.
    #
    # @param prompt (see LLM::Provider#complete)
    # @param params The params, including optional :role (defaults to :user), :stream, :tools, :schema etc.
    # @return [LLM::Response] Returns the LLM's response for this turn.
    # @example
    #   llm = LLM.openai(key: ENV["KEY"])
    #   ctx = LLM::Context.new(llm)
    #   res = ctx.talk("Hello, what is your name?")
    #   puts res.messages[0].content
    def talk(prompt, params = {})
      @owner = @llm.request_owner
      @compactor[:klass].new(self).call(**@compactor[:options])
      repair!(@messages, prompt)
      prompt, params, res = try { mode == :responses ? respond(prompt, params) : complete(prompt, params) }
      self.compacted = false
      if prompt.all?(&:tool_return?)
        @messages.concat prompt.map { LLM::Message.new(@llm.tool_role, _1.content, _1.extra) }
      else
        @messages.concat(prompt)
      end
      @messages.concat([res.choices[-1]].compact)
      stream.on_step(self, res)
      res
    ensure
      @owner = nil
    end

    ##
    # Ask a question and return the content string directly.
    # Accepts `with:` for file attachments and a block for streaming.
    # This interface is compatible with RubyLLM's `ask` method.
    #
    # @param [String] prompt
    # @param [Hash] options
    # @option options [String, Array<String>, nil] :with
    #  File path(s) to attach
    # @option options [#<<, LLM::Stream, nil] :stream
    #  A stream target
    # @yield [String] content chunks when streaming
    # @return [LLM::Response]
    def ask(prompt, options = {}, &block)
      options = {with: nil, stream: nil}.merge!(options || {})
      with, stream = options.values_at(:with, :stream)
      prompt = with ? [prompt, [*with].map { local_file(_1) }] : prompt
      target = if block
        blk = block.dup
        blk.singleton_class.alias_method(:<<, :call)
        blk
      else
        stream
      end
      target ? talk(prompt, stream: target) : talk(prompt)
    end

    ##
    # @return [String]
    def inspect
      "#<#{LLM::Utils.object_id(self)} " \
      "@llm=#{@llm.class}, @mode=#{@mode.inspect}, @params=#{@params.inspect}, " \
      "@messages=#{@messages.inspect}>"
    end

    ##
    # Returns an array of functions that can be called
    # @return [Array<LLM::Function>]
    def pending_functions
      return_ids = returns.map(&:id)
      guard = @guard[:klass].new(self)
      @messages
        .select(&:assistant?)
        .flat_map do |msg|
          fns = msg.functions.select { _1.pending? && !return_ids.include?(_1.id) }
          fns.each do |fn|
            fn.tracer = tracer
            fn.model  = msg.model
            fn.guard  = guard
          end
        end.extend(LLM::Function::Array)
    end

    ##
    # Returns whether there is pending tool work in this context.
    # This prefers queued streamed tool work when present, and otherwise
    # falls back to unresolved functions derived from the message history.
    # @return [Boolean]
    def pending_functions?
      pending = queue
      (pending && !pending.empty?) || pending_functions.any?
    end

    ##
    # Spawns a function through the context.
    #
    # @param [LLM::Function] function
    # @param [Symbol] strategy
    # @return [LLM::Function::Task]
    def spawn(function, strategy)
      function.task(strategy)
    end

    ##
    # Returns tool returns accumulated in this context
    # @return [Array<LLM::Function::Return>]
    def returns
      @messages
        .select(&:tool_return?)
        .flat_map do |msg|
          LLM::Function::Return === msg.content ?
            [msg.content] :
            [*msg.content].grep(LLM::Function::Return)
        end
    end

    ##
    # Waits for queued tool work to finish.
    #
    # This prefers queued streamed tool work when the configured stream
    # exposes a non-empty queue. Otherwise it falls back to waiting on
    # the context's pending functions directly.
    #
    # @param [Symbol, Array<Symbol>] strategy
    #  If the stream queue already has tool work, `wait` will drain it
    #  without using this argument.
    #  Otherwise, this controls how pending functions are resolved directly.
    #  Use `:sequential` for sequential execution without spawning.
    # @param [Array<LLM::Function>] except
    #  A list of functions to exclude from the wait
    # @return [Array<LLM::Function::Return>]
    def wait(strategy, except: [])
      if stream.queue.empty?
        ##
        # Every pending function is spawned as a task that checks its own
        # guard (stamped on the function) before running. Blocked tasks
        # yield their guard's return, so all pending calls still close.
        tools = except.empty? ? pending_functions : pending_functions - except
        @queue = tools.task(strategy)
        returns = @queue.wait
        emit_tool_returns(tools, returns)
        returns
      else
        @queue = stream.queue
        @queue.wait
      end
    rescue LLM::Interrupt
      ##
      # Once, not once per tool. A cancel reaches every tool that is
      # running, and the caller hears one exception, so the phase is
      # announced here - the frame every strategy's interrupt unwinds
      # through - and before the caller is given it.
      tracer.on_interrupt(scope: :tool)
      raise
    ensure
      @queue = nil
      @stream = nil
    end

    ##
    # Interrupt a turn: the request in flight, the tools that are
    # running, and - when it is neither of those - the caller the turn is
    # running under.
    #
    # This is inspired by Go's context cancellation model, and the three
    # are the whole of what a turn is doing. A request is closed at the
    # socket, which is `llm.interrupt!(owner)`: the transport keys its
    # live requests by the owner the request was made on, and answers
    # that it has nothing to close when there is no request registered
    # under it. A tool is a task, and every task that is running is
    # raised into. Between the two there is nothing: the loop is between
    # two requests, or waiting out a retry, or building the next one -
    # and until {LLM::Agent#run_loop} recorded the caller it is running
    # under, an interrupt there was a cancel that did nothing at all.
    #
    # The caller is the last resort rather than the first: the two precise
    # interrupts are what close a socket and stop a tool, and what is left
    # over is a turn that is running with nothing to point at. Ending that
    # is what the caller is asked to do - it answers `interrupt!`, announces
    # the phase to the tracer, and which of the thread, the fiber and the
    # scheduler it holds receives the raise is its own business. See
    # {LLM::Agent::Interrupt}.
    # @return [nil]
    def interrupt!
      llm.interrupt!(@owner)
      queue&.interrupt!
      pending_functions.each(&:interrupt!)
      @queue = nil
      @owner = nil
      @caller&.interrupt!
      nil
    end
    alias_method :cancel!, :interrupt!

    ##
    # Returns token usage accumulated in this context
    # @return [LLM::Usage]
    def token_usage
      @messages
        .select(&:assistant?)
        .map(&:token_usage)
        .compact
        .reduce(LLM::Usage.zero, :+)
    end
    alias_method :usage, :token_usage

    ##
    # @return [Integer, nil]
    #  Returns the live context size (in tokens) of the most
    #  recent assistant message.
    def context_used
      @messages
        .find(&:assistant?)
        &.token_usage
        &.total_tokens
    end

    ##
    # @return [Rational, nil]
    #  Returns the fraction of the context window currently used.
    #  For example: Rational(100, 10_000), or nil when unknown
    def context_usage
      return nil if @messages.size < 2
      used = context_used
      return nil if used.nil?
      total = context_window
      total.nil? || total <= 0 ? nil : Rational(used, total)
    rescue LLM::NoSuchModelError, LLM::NoSuchRegistryError
      nil
    end

    ##
    # Returns the model's context window.
    # The context window is the maximum amount of input and output
    # tokens a model can consider in a single request.
    # @note
    #  This method returns nil when the context window size
    #  is not known to the runtime
    # @return [Integer, nil]
    def context_window
      registry
        .limit(model:)
        .context
    rescue LLM::NoSuchModelError, LLM::NoSuchRegistryError
      nil
    end

    ##
    # Build a role-aware prompt for a single request.
    #
    # Prefer this method over {#build_prompt}. The older
    # method name is kept for backward compatibility.
    # @example
    #   prompt = ctx.prompt do
    #     system "Your task is to assist the user"
    #     user "Hello, can you assist me?"
    #   end
    #   ctx.talk(prompt)
    # @param [Proc] b
    #  A block that composes messages. If it takes one argument,
    #  it receives the prompt object. Otherwise it runs in prompt context.
    # @return [LLM::Prompt]
    def prompt(&b)
      LLM::Prompt.new(@llm, &b)
    end
    alias_method :build_prompt, :prompt

    ##
    # Recongize an object as a URL to an image
    # @param [String] url
    #  The URL
    # @return [LLM::Object]
    #  Returns a tagged object
    def image_url(url)
      LLM::Object.from(value: url, kind: :image_url)
    end

    ##
    # Recongize an object as a local file
    # @param [String] path
    #  The path
    # @return [LLM::Object]
    #  Returns a tagged object
    def local_file(path)
      LLM::Object.from(value: LLM.File(path), kind: :local_file)
    end

    ##
    # Reconginize an object as a remote file
    # @param [LLM::Response] res
    #  The response
    # @return [LLM::Object]
    #  Returns a tagged object
    def remote_file(res)
      LLM::Object.from(value: res, kind: :remote_file)
    end

    ##
    # @return [LLM::Tracer]
    #  Returns an LLM tracer
    def tracer
      @llm.tracer
    end

    ##
    # @param [LLM::Tracer, nil] other
    #  A tracer, or nil.
    # @return [void]
    def tracer=(other)
      @llm.tracer = other || LLM::Tracer::Null.new(@llm)
    end

    ##
    # @return [LLM::Stream, #<<, nil]
    #  Returns a stream object, or nil
    def stream
      @stream || @params[:stream]
    end

    ##
    # Returns the model a Context is actively using
    # @return [String]
    def model
      messages.find(&:assistant?)&.model || @params[:model] || @llm.default_model
    end

    ##
    # Returns the time this context was created, derived from the
    # timestamp embedded in its UUIDv7 id, or nil when it is not.
    # @return [Time, nil]
    def created_at
      @created_at ||= LLM::Utils.timestamp(@id)
    end

    ##
    # Returns the runtime state as a Hash.
    #
    # `context_used` and `context_window` are projections written for
    # queryability, so that saved state can be inspected at rest
    # without loading it. They are never read back; the runtime
    # always derives them from the messages and the registry.
    # @return [Hash]
    def to_h
      {
        schema_version: 1,
        id: @id,
        model:,
        compacted:,
        context_used:,
        context_window:,
        messages: @messages.map { serialize_message(_1) }
      }
    end

    ##
    # @return [String]
    def to_json(...)
      LLM.json.dump(to_h, ...)
    end

    ##
    # Save the current context state
    # @example
    #  llm = LLM.openai(key: ENV["KEY"])
    #  ctx = LLM::Context.new(llm)
    #  ctx.talk "Hello"
    #  ctx.save(path: "context.json")
    # @raise [SystemCallError]
    #  Might raise a number of SystemCallError subclasses
    # @return [void]
    def serialize(path:)
      ::File.binwrite path, LLM.json.dump(to_h)
    end
    alias_method :save, :serialize

    ##
    # @return [LLM::Cost]
    #  Returns an _approximate_ cost for a given context
    #  based on both the provider, and model
    def cost
      LLM::Cost.from(self)
    end

    ##
    # @see LLM::Provider#registry
    # @return [LLM::Registry]
    def registry
      llm.registry
    end

    private

    ##
    # Returns the bound stream queue, if available.
    # @api private
    def queue
      [@queue, stream.queue].compact.first
    end

    ##
    # The id a context is born with.
    #
    # The record's id when the context is bound to a record and that id
    # is a UUIDv7, so that an agent and the row it came from answer the
    # same name - and a generated UUIDv7 otherwise, which is every
    # context with no record, every record whose id is an integer or a
    # slug, and every row that is not saved yet.
    #
    # The check is the same function {#created_at} reads a time out of,
    # rather than a second opinion about what a UUIDv7 looks like: an id
    # this accepts is an id `created_at` can answer for.
    # @api private
    # @return [Object]
    def makeid
      if record
        LLM::Utils.timestamp(record.id) ? record.id : SecureRandom.uuid_v7
      else
        SecureRandom.uuid_v7
      end
    end

    ##
    # Loads skill directories and adapts them into tools.
    # @api private
    def load_skills(skills)
      [*skills].map { LLM::Skill.load(_1).to_tool(self) }
    end

    ##
    # Rewrites a prompt and params through the configured transformer.
    # @api private
    def transform(prompt, params, key: :messages)
      transformer = @transformer[:klass].new(self)
      stream = params[:stream]
      stream.on_transform(transformer)
      role = params[:role] || @llm.user_role
      messages = @llm.build_messages(prompt, params, role, key:)
      messages[-1] = transformer.call(message: messages[-1], **@transformer[:options])
      messages
    ensure
      stream.on_transform_finish(transformer)
    end

    ##
    #
    # Runs a network call, retrying it when the request is rate limited
    # ({LLM::RateLimitError}) or times out (`Timeout::Error`, which covers
    # `Net::OpenTimeout` and `Net::ReadTimeout`), up to the retry budget.
    # Each retry notifies the stream and sleeps a growing interval
    # (2s, 4s, 6s, ...) rather than the server's `retry_after`. A 429 is
    # refused before any content streams, so retrying the same request
    # loses nothing. The bare `retry` below re-runs the method body while
    # `attempts ||= 0` keeps the count across attempts.
    #
    # The sleep is interruptible, which is the reason it needs nothing
    # else: a cancel that arrives here has no request in flight to close
    # and no tool to raise into, so it is the caller that is raised into -
    # and a thread or fiber that is sleeping receives it the way it would
    # receive it anywhere else. A turn cancelled between two attempts
    # does not make the next one.
    # @api private
    # @return [Object]
    def try
      attempts ||= 0
      yield
    rescue => ex
      case ex.class.to_s
      when *TRY_ERRORS
        raise if attempts >= retry_budget
        attempts += 1
        stream.on_retry(ex, attempts)
        sleep 2.0 * attempts
        retry
      else
        raise(ex)
      end
    end

    # Executes a turn through the Responses API.
    # @api private
    def respond(prompt, params)
      @llm.with(**headers) do
        history = @messages.to_a
        params = @params.merge(params).reject { self.class.params.include?(_1.to_s) }
        extra = params.slice(:model, :tools).merge!(ctx: self, tracer:, guard: @guard[:klass].new(self))
        params[:stream] = LLM::Stream.try(params[:stream], extra:)
        res_id = params[:store] == false ? nil : @messages.find(&:assistant?)&.response&.response_id
        input = res_id ? [] : history
        params[:input] = input
        messages = transform(prompt, params, key: :input)
        @stream = params[:stream]
        new_messages = messages[input.size..]
        params = params.merge(previous_response_id: res_id, input:).compact
        [new_messages, params, @llm.responses.create(messages, params)]
      end
    end

    ##
    # Executes a turn through the chat completions API.
    # @api private
    def complete(prompt, params)
      @llm.with(**headers) do
        history = @messages.to_a
        params = params.merge(messages: history)
        params = @params.merge(params).reject { self.class.params.include?(_1.to_s) }
        extra = params.slice(:model, :tools).merge!(ctx: self, tracer:, guard: @guard[:klass].new(self))
        params[:stream] = LLM::Stream.try(params[:stream], extra:)
        messages = transform(prompt, params)
        @stream = params[:stream]
        new_messages = messages[history.size..]
        [new_messages, params, @llm.complete(messages, params)]
      end
    end

    ##
    # Emits tool return callbacks for directly waited function work.
    # @api private
    def emit_tool_returns(tools, returns)
      returns.each_with_index { |result, index| stream.on_tool_return(tools[index], result) }
    end

    ##
    # Closes assistant tool-call messages that do not have matching tool
    # responses. This can happen when a turn is interrupted while a tool
    # call is streaming or waiting for user confirmation.
    # @param [Array<LLM::Message>] messages
    # @param [Object] prompt
    # @return [void]
    def repair!(messages, prompt)
      message = messages.last
      return unless message&.tool_call?
      returns = [self.returns, prompt].flatten.grep(LLM::Function::Return)
      cancelled = []
      [*message.extra.tool_calls].each do |tool|
        next if returns.any? { _1.id == tool[:id] }
        attrs = {cancelled: true, reason: "function call cancelled"}
        cancelled << LLM::Function::Return.new(tool[:id], tool[:name], attrs)
      end
      messages << LLM::Message.new(@llm.tool_role, cancelled) unless cancelled.empty?
    end

    ##
    # @return [Hash]
    def headers
      if @llm.name == :openrouter
        {"x-session-id" => @id}
      else
        {}
      end
    end
  end
end
