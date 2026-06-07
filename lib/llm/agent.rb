# frozen_string_literal: true

module LLM
  ##
  # {LLM::Agent LLM::Agent} provides a class-level DSL for defining
  # reusable, preconfigured assistants with defaults for model,
  # tools, schema, and instructions.
  #
  # It wraps the same stateful runtime surface as
  # {LLM::Context LLM::Context}: message history, usage, persistence,
  # streaming parameters, and provider-backed requests still flow through
  # an underlying context. The defining behavior of an agent is that it
  # automatically resolves pending tool calls for you during `talk` and
  # `respond`, instead of leaving tool loops to the caller.
  #
  # **Notes:**
  # * Instructions are injected once unless a system message is already present.
  # * An agent automatically executes tool loops (unlike {LLM::Context LLM::Context}).
  # * The automatic tool loop enables the wrapped context's `guard` by default.
  #   The built-in {LLM::LoopGuard LLM::LoopGuard} detects repeated tool-call
  #   patterns and blocks stuck execution before more tool work is queued.
  # * The default tool attempt budget is `25`. After that, the agent sends
  #   advisory tool errors back through the model and keeps the loop in-band.
  #   Set `tool_attempts: nil` to disable that advisory behavior.
  # * Tool loop execution can be configured with `concurrency :call`,
  #   `:thread`, `:task`, `:fiber`, or `:ractor`.
  #
  # @example
  #   class SystemAdmin < LLM::Agent
  #     model "gpt-4.1-nano"
  #     instructions "You are a Linux system admin"
  #     tools Shell
  #     schema Result
  #   end
  #
  #   llm = LLM.openai(key: ENV["KEY"])
  #   agent = SystemAdmin.new(llm)
  #   agent.talk("Run 'date'")
  class Agent
    ##
    # Returns a provider
    # @return [LLM::Provider]
    attr_reader :llm

    ##
    # Set or get the default model
    # @param [String, nil] model
    #  The model identifier
    # @return [String, nil]
    #  Returns the current model when no argument is provided
    def self.model(model = nil, &block)
      return @model if model.nil? && !block
      @model = block || model
    end

    ##
    # Set or get the default tools
    # @param [Array<LLM::Function>, nil] tools
    #  One or more tools
    # @return [Array<LLM::Function>]
    #  Returns the current tools when no argument is provided
    def self.tools(*tools, &block)
      return @tools || [] if tools.empty? && !block
      @tools = block || tools.flatten
    end

    ##
    # Set or get the default skills
    # @param [Array<String>, nil] skills
    #  One or more skill directories
    # @return [Array<String>, nil]
    #  Returns the current skills when no argument is provided
    def self.skills(*skills, &block)
      return @skills if skills.empty? && !block
      if skills.size == 1 and skills.grep(Symbol).any?
        @skills = skills.first
      else
        @skills = block || skills.flatten
      end
    end

    ##
    # Set or get the default schema
    # @param [#to_json, nil] schema
    #  The schema
    # @return [#to_json, nil]
    #  Returns the current schema when no argument is provided
    def self.schema(schema = nil, &block)
      return @schema if schema.nil? && !block
      @schema = block || schema
    end

    ##
    # Set or get the default instructions
    # @param [String, nil] instructions
    #  The system instructions
    # @return [String, nil]
    #  Returns the current instructions when no argument is provided
    def self.instructions(instructions = nil)
      return @instructions if instructions.nil?
      @instructions = instructions
    end

    ##
    # Set or get the tool execution concurrency.
    #
    # @param [Symbol, Array<Symbol>, nil] concurrency
    #  Controls how pending tool loops are executed:
    #  - `:call`: sequential calls
    #  - `:thread`: concurrent threads
    #  - `:task`: concurrent async tasks
    #  - `:fiber`: concurrent scheduler-backed fibers
    #  - `:fork`: forked child processes
    #  - `:ractor`: concurrent Ruby ractors for class-based tools; MCP tools are not supported,
    #    and this mode is especially useful for CPU-bound tool work
    #  Usually pass a single strategy. Arrays are only for advanced mixed-work
    #  cases and are not needed for normal queued stream tool loops.
    # @return [Symbol, Array<Symbol>, nil]
    def self.concurrency(concurrency = nil)
      return @concurrency if concurrency.nil?
      @concurrency = concurrency
    end

    ##
    # Set or get the default tracer.
    #
    # When a block is provided, it is stored and evaluated lazily against the
    # agent instance during initialization so it can build a tracer from the
    # resolved provider.
    #
    # @example
    #   class Agent < LLM::Agent
    #     tracer { LLM::Tracer::Logger.new(llm, io: $stdout) }
    #   end
    #
    # @param [LLM::Tracer, Proc, nil] tracer
    # @yieldreturn [LLM::Tracer, nil]
    # @return [LLM::Tracer, Proc, nil]
    def self.tracer(tracer = nil, &block)
      return @tracer if tracer.nil? && !block
      @tracer = block || tracer
    end

    ##
    # Set or get the default stream.
    #
    # When a block is provided, it is stored and evaluated lazily against the
    # agent instance during initialization so it can build a fresh stream for
    # each agent.
    #
    # @example
    #   class Agent < LLM::Agent
    #     stream { MyStream.new }
    #   end
    #
    # @param [Object, Proc, nil] stream
    # @yieldreturn [Object, nil]
    # @return [Object, Proc, nil]
    def self.stream(stream = nil, &block)
      return @stream if stream.nil? && !block
      @stream = block || stream
    end

    ##
    # Set or get the tool names that require confirmation before they can run.
    #
    # When a single Symbol is given, it is stored as-is and resolved at
    # initialization time by calling the method with that name on the agent
    # instance. This allows dynamic tool confirmation lists.
    #
    # @example
    #   class MyAgent < LLM::Agent
    #     confirm :tools_that_need_confirmation
    #
    #     def tools_that_need_confirmation
    #       some_condition ? %w[delete destroy] : %w[delete]
    #     end
    #   end
    #
    # @param [String, Symbol, Array<String, Symbol>, Proc] tool_names
    #  One or more tool names.
    # @param [Proc] block
    #  An optional, lazy-evaluated Proc
    # @return [Array<String>, Proc, Symbol, nil]
    def self.confirm(*tool_names, &block)
      return @confirm if tool_names.empty? && !block
      if tool_names.size == 1 && tool_names.grep(Symbol).any?
        @confirm = tool_names.first
      else
        @confirm = block || tool_names.flatten.map(&:to_s)
      end
    end

    ##
    # @param [LLM::Provider] provider
    #  A provider
    # @param [Hash] params
    #  The parameters to maintain throughout the conversation.
    #  Any parameter the provider supports can be included and
    #  not only those listed here.
    # @option params [String] :model Defaults to the provider's default model
    # @option params [Array<LLM::Function>, nil] :tools Defaults to nil
    # @option params [Array<String>, nil] :skills Defaults to nil
    # @option params [#to_json, nil] :schema Defaults to nil
    # @option params [Object, Proc, nil] :stream Optional stream override for this agent instance
    # @option params [LLM::Tracer, Proc, nil] :tracer Optional tracer override for this agent instance
    # @option params [Symbol, Array<Symbol>, nil] :concurrency Defaults to the agent class concurrency
    def initialize(llm, params = {})
      @llm = llm
      fields = %i[model skills schema tracer stream tools concurrency instructions confirm]
      fields_ivar = %i[tracer concurrency instructions confirm]
      fields.each do |field|
        resolvable = params.key?(field) ? params.delete(field) : self.class.public_send(field)
        resolve_symbol = !%i[concurrency].include?(field)
        resolved = resolvable != nil ? resolve_option(self, resolvable, resolve_symbol:) : resolvable
        resolved = [*resolved].map(&:to_s) if field == :confirm && resolved
        if field == :model
          params[field] = resolved unless resolved.nil? || params.key?(field)
        elsif resolved && !fields_ivar.include?(field)
          params[field] ||= resolved
        elsif fields_ivar.include?(field)
          instance_variable_set(:"@#{field}", resolved)
        end
      end
      @ctx = LLM::Context.new(llm, {guard: true}.merge(params))
    end

    ##
    # Maintain a conversation via the chat completions API.
    # This method immediately sends a request to the LLM and returns the response.
    #
    # @param prompt (see LLM::Provider#complete)
    # @param [Hash] params The params passed to the provider, including optional :stream, :tools, :schema etc.
    # @option params [Integer] :tool_attempts
    #  The maxinum number of tool call iterations before the agent sends
    #  in-band advisory tool errors back through the model (default 25).
    #  Set to `nil` to disable advisory tool-limit returns.
    # @return [LLM::Response] Returns the LLM's response for this turn.
    # @example
    #   llm = LLM.openai(key: ENV["KEY"])
    #   agent = LLM::Agent.new(llm)
    #   response = agent.talk("Hello, what is your name?")
    #   puts response.choices[0].content
    def talk(prompt, params = {})
      run_loop(prompt, params, :talk)
    end

    ##
    # @see LLM::Context#ask
    def ask(prompt, params = {})
      run_loop(prompt, params, :ask)
    end

    ##
    # @return [LLM::Buffer<LLM::Message>]
    def messages
      @ctx.messages
    end

    ##
    # @return [Array<LLM::Function>]
    def functions
      @tracer ? @llm.with_tracer(@tracer) { @ctx.functions } : @ctx.functions
    end

    ##
    # @see LLM::Context#returns
    # @return [Array<LLM::Function::Return>]
    def returns
      @ctx.returns
    end

    ##
    # @see LLM::Context#wait
    # @return [Array<LLM::Function::Return>]
    def wait(...)
      @tracer ? @llm.with_tracer(@tracer) { @ctx.wait(...) } : @ctx.wait(...)
    end

    ##
    # @return [LLM::Object]
    def usage
      @ctx.usage
    end

    ##
    # Interrupt the active request, if any.
    # @return [nil]
    def interrupt!
      @ctx.interrupt!
    end
    alias_method :cancel!, :interrupt!

    ##
    # @param (see LLM::Context#prompt)
    # @return (see LLM::Context#prompt)
    # @see LLM::Context#prompt
    def prompt(&b)
      @ctx.prompt(&b)
    end
    alias_method :build_prompt, :prompt

    ##
    # @param [String] url
    #  The URL
    # @return [LLM::Object]
    #  Returns a tagged object
    def image_url(url)
      @ctx.image_url(url)
    end

    ##
    # @param [String] path
    #  The path
    # @return [LLM::Object]
    #  Returns a tagged object
    def local_file(path)
      @ctx.local_file(path)
    end

    ##
    # @param [LLM::Response] res
    #  The response
    # @return [LLM::Object]
    #  Returns a tagged object
    def remote_file(res)
      @ctx.remote_file(res)
    end

    ##
    # @return [LLM::Tracer]
    #  Returns an LLM tracer
    def tracer
      @tracer || @ctx.tracer
    end

    ##
    # @return [LLM::Stream, #<<, nil]
    #  Returns a stream object, or nil
    def stream
      @ctx.stream
    end

    ##
    # Returns the model an Agent is actively using
    # @return [String]
    def model
      @ctx.model
    end

    ##
    # @return [Symbol]
    def mode
      @ctx.mode
    end

    ##
    # Returns the configured tool execution concurrency.
    # @return [Symbol, Array<Symbol>, nil]
    def concurrency
      @concurrency
    end

    ##
    # @see LLM::Context#cost
    # @return [LLM::Cost]
    def cost
      @ctx.cost
    end

    ##
    # @see LLM::Context#context_window
    # @return [Integer]
    def context_window
      @ctx.context_window
    end

    ##
    # @see LLM::Context#params
    # @return [Hash]
    def params
      @ctx.params
    end

    ##
    # @see LLM::Context#to_h
    # @return [Hash]
    def to_h
      @ctx.to_h
    end

    ##
    # @return [String]
    def to_json(...)
      LLM.json.dump(to_h, ...)
    end

    ##
    # @return [String]
    def inspect
      "#<#{LLM::Utils.object_id(self)} " \
      "@llm=#{@llm.class}, @mode=#{mode.inspect}, @messages=#{messages.inspect}>"
    end

    ##
    # @param (see LLM::Context#serialize)
    # @return (see LLM::Context#serialize)
    def serialize(**kw)
      @ctx.serialize(**kw)
    end
    alias_method :save, :serialize

    ##
    # @param (see LLM::Context#deserialize)
    # @return (see LLM::Context#deserialize)
    def deserialize(**kw)
      @ctx.deserialize(**kw)
    end
    alias_method :restore, :deserialize

    ##
    # This method is called when confirmation is required before a tool can run.
    #
    # @param [LLM::Function] fn
    #  The pending function call. It can be cancelled through the
    #  {LLM::Function#cancel} method.
    # @param [Symbol, Array<Symbol>] strategy
    #  The execution strategy that would be used for the tool call.
    # @return [LLM::Function::Return]
    #  Return either `fn.spawn(strategy).wait` to approve execution or
    #  `fn.cancel(...)` to cancel the call.
    def on_tool_confirmation(fn, strategy)
      fn.cancel
    end

    private

    ##
    # @return [LLM::Prompt]
    def apply_instructions(new_prompt)
      return new_prompt unless @instructions
      if LLM::Prompt === new_prompt
        new_prompt.system(@instructions) if inject_instructions?(new_prompt)
        new_prompt
      else
        prompt do
          _1.system(@instructions) if inject_instructions?
          _1.user(new_prompt)
        end
      end
    end

    ##
    # Returns true when agent instructions should be injected for the turn.
    # Instructions are injected once unless a system message is already
    # present in the existing context or the prompt being sent.
    # @param [LLM::Prompt, nil] prompt
    # @return [Boolean]
    def inject_instructions?(prompt = nil)
      return false if @ctx.messages.any?(&:system?)
      return true if prompt.nil?
      !prompt.to_a.any?(&:system?)
    end

    ##
    # @return [Array<LLM::Function::Return>]
    def call_functions
      strategy = concurrency || :call
      return wait(strategy) unless @confirm&.any?
      confirmables = @ctx.functions.select { @confirm.include?(_1.name.to_s) }
      results = confirmables.map { method(:on_tool_confirmation).call(_1, strategy) }
      @ctx.method(:emit_tool_returns).call(confirmables, results)
      if (@ctx.functions - confirmables).any?
        [*results, *wait(strategy, except: confirmables)]
      else
        results
      end
    end

    ##
    # Runs the tool loop
    # @api private
    def run_loop(prompt, params, target)
      run = proc do
        talk = @ctx.method(target)
        max = params.key?(:tool_attempts) ? params.delete(:tool_attempts) : 25
        max = Integer(max) if max
        stream = params[:stream] || @ctx.params[:stream]
        stream.extra[:concurrency] = concurrency if LLM::Stream === stream
        res = talk.call(apply_instructions(prompt), params)
        while @ctx.functions?
          if max
            max.times do
              break unless @ctx.functions?
              res = talk.call(call_functions, params)
            end
            res = talk.call(@ctx.functions.map(&:rate_limit), params) if @ctx.functions?
          else
            res = talk.call(call_functions, params)
          end
        end
        res
      end
      return run.call unless @tracer
      @llm.with_tracer(@tracer, &run)
    end

    ##
    # @api private
    def resolve_option(...)
      LLM::Utils.resolve_option(...)
    end
  end
end
