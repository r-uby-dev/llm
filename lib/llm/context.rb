# frozen_string_literal: true

module LLM
  ##
  # {LLM::Context LLM::Context} is the stateful execution boundary in
  # llm.rb.
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
  #   llm = LLM.openai(key: ENV["KEY"])
  #   ctx = LLM::Context.new(llm)
  #
  #   prompt = LLM::Prompt.new(llm) do
  #     system "Be concise and show your reasoning briefly."
  #     user "If a train goes 60 mph for 1.5 hours, how far does it travel?"
  #     user "Now double the speed for the same time."
  #   end
  #
  #   ctx.talk(prompt)
  #   ctx.messages.each { |m| puts "[#{m.role}] #{m.content}" }
  class Context
    require_relative "compactor"
    require_relative "context/serializer"
    require_relative "context/deserializer"
    include Serializer
    include Deserializer

    ZERO_USAGE = LLM::Object.from(
      input_tokens: 0,
      output_tokens: 0,
      reasoning_tokens: 0,
      input_audio_tokens: 0,
      output_audio_tokens: 0,
      input_image_tokens: 0,
      cache_read_tokens: 0,
      cache_write_tokens: 0,
      total_tokens: 0
    )
    private_constant :ZERO_USAGE

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
    # @option params [Array<LLM::Function>, nil] :tools Defaults to nil
    # @option params [Array<String>, nil] :skills Defaults to nil
    def initialize(llm, params = {})
      @llm = llm
      @mode = params.delete(:mode) || (llm.name == :openai ? :responses : :completions)
      @compactor = params.delete(:compactor)
      @guard = params.delete(:guard)
      @transformer = params.delete(:transformer)
      tools = [*params.delete(:tools), *load_skills(params.delete(:skills))]
      @params = {model: llm.default_model, schema: nil}.compact.merge!(params)
      @params[:tools] = tools unless tools.empty?
      @params[:store] ||= false if @mode == :responses
      @messages = LLM::Buffer.new(llm)
    end

    ##
    # Returns the default params for this context
    # @return [Hash]
    def params
      @params.dup
    end

    ##
    # Returns a context compactor
    # This feature is inspired by the compaction approach developed by
    # General Intelligence Systems.
    # @return [LLM::Compactor]
    def compactor
      @compactor = LLM::Compactor.new(self, @compactor || {}) unless LLM::Compactor === @compactor
      @compactor
    end

    ##
    # Sets a context compactor or compactor config
    # @param [LLM::Compactor, Hash, nil] compactor
    # @return [LLM::Compactor, Hash, nil]
    def compactor=(compactor)
      @compactor = compactor
    end

    ##
    # Returns whether the context has been compacted and no later model
    # response has cleared that state.
    # @return [Boolean]
    # @api private
    attr_accessor :compacted
    alias_method :compacted?, :compacted

    ##
    # Returns a guard, if configured.
    #
    # Guards are context-level supervisors for agentic execution. A guard can
    # inspect the runtime state and decide whether pending tool work should be
    # blocked before the context keeps looping.
    #
    # The built-in implementation is {LLM::LoopGuard LLM::LoopGuard}, which
    # detects repeated tool-call patterns and turns them into in-band
    # {LLM::GuardError LLM::GuardError} tool returns.
    #
    # @return [#call, nil]
    def guard
      return if @guard.nil? || @guard == false
      @guard = LLM::LoopGuard.new if @guard == true
      @guard = LLM::LoopGuard.new(@guard) if Hash === @guard
      @guard
    end

    ##
    # Sets a guard or guard config.
    #
    # Guards must implement `call(ctx)` and return either `nil` or a warning
    # string. Returning a warning tells the context to block pending tool work
    # with guarded tool errors instead of continuing the loop.
    #
    # @param [#call, Hash, Boolean, nil] guard
    # @return [#call, Hash, Boolean, nil]
    def guard=(guard)
      @guard = guard
    end

    ##
    # Returns a transformer, if configured.
    #
    # Transformers can rewrite outgoing prompts and params before a request is
    # sent to the provider.
    #
    # @return [#call, nil]
    def transformer
      @transformer
    end

    ##
    # Sets a transformer.
    #
    # Transformers must implement `call(ctx, prompt, params)` and return a
    # two-element array of `[prompt, params]`.
    #
    # @param [#call, nil] transformer
    # @return [#call, nil]
    def transformer=(transformer)
      @transformer = transformer
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
      compactor.compact!(prompt) if compactor.compact?(prompt)
      repair!(@messages, prompt)
      prompt, params, res = mode == :responses ? respond(prompt, params) : complete(prompt, params)
      self.compacted = false
      role = params[:role] || @llm.user_role
      role = @llm.tool_role if params[:role].nil? && [*prompt].grep(LLM::Function::Return).any?
      @messages.concat LLM::Prompt === prompt ? prompt.to_a : [LLM::Message.new(role, prompt)]
      @messages.concat [res.choices[-1]].compact
      res
    end

    ##
    # Ask a question and return the content string directly.
    # Accepts `with:` for file attachments and a block for streaming.
    # This interface is compatible with RubyLLM's `ask` method.
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
    def functions
      return_ids = returns.map(&:id)
      @messages
        .select(&:assistant?)
        .flat_map do |msg|
          fns = msg.functions.select { _1.pending? && !return_ids.include?(_1.id) }
          fns.each do |fn|
            fn.tracer = tracer
            fn.model  = msg.model
          end
        end.extend(LLM::Function::Array)
    end

    ##
    # Returns whether there is pending tool work in this context.
    # This prefers queued streamed tool work when present, and otherwise
    # falls back to unresolved functions derived from the message history.
    # @return [Boolean]
    def functions?
      pending = queue
      (pending && !pending.empty?) || functions.any?
    end

    ##
    # Spawns a function through the context.
    #
    # When a guard is configured, this method can return an in-band guarded
    # tool error instead of spawning work.
    #
    # @param [LLM::Function] function
    # @param [Symbol] strategy
    # @return [LLM::Function::Return, LLM::Function::Task]
    def spawn(function, strategy)
      warning = guard&.call(self)
      return guarded_return_for(function, warning) if warning
      function.spawn(strategy)
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
    #  Use `:call` for sequential execution without spawning.
    # @param [Array<LLM::Function>] except
    #  A list of functions to exclude from the wait
    # @return [Array<LLM::Function::Return>]
    def wait(strategy, except: [])
      if LLM::Stream === stream && !stream.queue.empty?
        @queue = stream.queue
        @queue.wait
      else
        tools  = except.empty? ? functions : functions - except
        guards = guarded_returns(tools:)
        return guards if guards
        @queue = tools.spawn(strategy)
        returns = @queue.wait
        emit_tool_returns(tools, returns)
        returns
      end
    ensure
      @queue = nil
      @stream = nil
    end

    ##
    # Interrupt the active request, if any.
    # This is inspired by Go's context cancellation model.
    # @return [nil]
    def interrupt!
      pending = functions.to_a
      llm.interrupt!(@owner)
      queue&.interrupt!
      return if pending.empty?
      pending.each(&:interrupt!)
      returns = pending.map { _1.cancel(reason: "function call cancelled") }
      @messages << LLM::Message.new(@llm.tool_role, returns)
      nil
    end
    alias_method :cancel!, :interrupt!

    ##
    # Returns token usage accumulated in this context
    # @return [LLM::Object]
    def usage
      if usage = @messages.find(&:assistant?)&.usage
        LLM::Object.from(
          input_tokens: usage.input_tokens || 0,
          output_tokens: usage.output_tokens || 0,
          reasoning_tokens: usage.reasoning_tokens || 0,
          input_audio_tokens: usage.input_audio_tokens || 0,
          output_audio_tokens: usage.output_audio_tokens || 0,
          input_image_tokens: usage.input_image_tokens || 0,
          cache_read_tokens: usage.cache_read_tokens || 0,
          cache_write_tokens: usage.cache_write_tokens || 0,
          total_tokens: usage.total_tokens || 0
        )
      else
        ZERO_USAGE
      end
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
    # @return [LLM::Stream, #<<, nil]
    #  Returns a stream object, or nil
    def stream
      @stream || @params[:stream]
    end

    ##
    # Returns the model a Context is actively using
    # @return [String]
    def model
      messages.find(&:assistant?)&.model || @params[:model]
    end

    ##
    # @return [Hash]
    def to_h
      {
        schema_version: 1,
        model:,
        compacted:,
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
    # Returns the model's context window.
    # The context window is the maximum amount of input and output
    # tokens a model can consider in a single request.
    # @note
    #   This method returns 0 when the provider or
    #   model can't be found within {LLM::Registry}.
    # @return [Integer]
    def context_window
      LLM
        .registry_for(llm)
        .limit(model:)
        .context
    rescue LLM::NoSuchModelError, LLM::NoSuchRegistryError
      0
    end

    private

    ##
    # Binds runtime metadata onto an active stream.
    # @api private
    def bind!(stream, model, tools)
      return unless LLM::Stream === stream
      @stream = stream
      stream.extra[:ctx] = self
      stream.extra[:tracer] = tracer
      stream.extra[:model] = model
      stream.extra[:tools] = tools
    end

    ##
    # Returns the bound stream queue, if available.
    # @api private
    def queue
      [@queue, stream&.queue].compact.first
    rescue NoMethodError
      nil
    end

    ##
    # Loads skill directories and adapts them into tools.
    # @api private
    def load_skills(skills)
      [*skills].map { LLM::Skill.load(_1).to_tool(self) }
    end

    ##
    # Builds in-band guarded returns when the guard blocks tool work.
    # @api private
    def guarded_returns(tools:)
      warning = guard&.call(self)
      return unless warning
      tools.map { guarded_return_for(_1, warning) }
    end

    ##
    # Rewrites a prompt and params through the configured transformer.
    # @api private
    def transform(prompt, params)
      return [prompt, params] unless transformer
      stream = params[:stream]
      stream.on_transform(self, transformer) if LLM::Stream === stream
      transformer.call(self, prompt, params)
    ensure
      stream.on_transform_finish(self, transformer) if LLM::Stream === stream
    end

    ##
    # Executes a turn through the Responses API.
    # @api private
    def respond(prompt, params)
      params = @params.merge(params)
      prompt, params = transform(prompt, params)
      bind!(params[:stream], params[:model], params[:tools])
      res_id = params[:store] == false ? nil : @messages.find(&:assistant?)&.response&.response_id
      input = res_id ? [] : @messages.to_a
      params = params.merge(previous_response_id: res_id, input:).compact
      [prompt, params, @llm.responses.create(prompt, params)]
    end

    ##
    # Executes a turn through the chat completions API.
    # @api private
    def complete(prompt, params)
      params = params.merge(messages: @messages.to_a)
      params = @params.merge(params)
      prompt, params = transform(prompt, params)
      bind!(params[:stream], params[:model], params[:tools])
      [prompt, params, @llm.complete(prompt, params)]
    end

    ##
    # Builds one guarded tool return for a blocked function call.
    # @api private
    def guarded_return_for(function, warning)
      LLM::Function::Return.new(function.id, function.name, {
        error: true,
        type: LLM::GuardError.name,
        message: warning
      })
    end

    ##
    # Emits tool return callbacks for directly waited function work.
    # @api private
    def emit_tool_returns(tools, returns)
      return unless LLM::Stream === stream
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
      returns = self.returns + [*prompt].grep(LLM::Function::Return)
      cancelled = []
      [*message.extra.tool_calls].each do |tool|
        next if returns.any? { _1.id == tool[:id] }
        attrs = {cancelled: true, reason: "function call cancelled"}
        cancelled << LLM::Function::Return.new(tool[:id], tool[:name], attrs)
      end
      messages << LLM::Message.new(@llm.tool_role, cancelled) unless cancelled.empty?
    end
  end
end
