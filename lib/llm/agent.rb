# frozen_string_literal: true

module LLM
  ##
  # {LLM::Agent LLM::Agent} is the recommended entry point for most
  # use-cases. It provides a class-level DSL for defining reusable,
  # preconfigured assistants with defaults for model, tools, schema,
  # and instructions.
  #
  # It wraps the same stateful runtime surface as
  # {LLM::Context LLM::Context}: message history, usage, persistence,
  # streaming parameters, and provider-backed requests still flow through
  # an underlying context. The defining behavior of an agent is that it
  # automatically resolves pending tool calls for you during `talk`,
  # instead of leaving tool loops to the caller.
  #
  # **Notes:**
  # * Instructions are injected once, and kept in step after that. A
  #   restored conversation carries the instructions that were current
  #   when it started, and the message is brought up to date before the
  #   next request goes out.
  # * An agent automatically executes tool loops (unlike {LLM::Context LLM::Context}).
  # * The tool loop can be bounded with `tool_budget`. Once the budget is
  #   spent, no further tool calls are run for that turn: the agent sends an
  #   in-band advisory message back through the model instead, and keeps
  #   sending it while the model keeps asking for tools. The budget counts
  #   tool calls, so a batch of calls is spent as a batch, and a batch that
  #   would take the turn past its budget is not run at all. By default no
  #   budget is set (`nil`), so the feature is disabled.
  # * Tool loop execution can be configured with `concurrency :sequential`,
  #   `:thread`, `:async`, `:fiber`, `:fork`, or `:ractor`.
  #
  # @example Subclass with defaults
  #   class SystemAdmin < LLM::Agent
  #     set model: "gpt-4.1-nano",
  #         instructions: "You are a Linux system admin",
  #         tools: [LLM::Tool::Exec],
  #         schema: Result
  #   end
  #
  #   llm = LLM.openai(key: ENV["KEY"])
  #   agent = SystemAdmin.new(llm)
  #   agent.talk("Run 'date'")
  #
  # @example Direct instance
  #   llm = LLM.deepseek(key: ENV["KEY"])
  #   agent = LLM::Agent.new(llm, stream: $stdout)
  #   agent.talk "Hello world"
  #
  # @see LLM::Context The low-level runtime that Agent wraps
  # @see LLM::Tool Tools that Agent can call on your behalf
  # @see LLM::Stream Stream callbacks for model output
  class Agent
    ##
    # @api private
    UNDEFINED = Object.new
    private_constant :UNDEFINED

    ##
    # Marks the message an agent injects as its own, so that a later
    # turn can tell it from a message the caller composed. The role
    # cannot do that: it is true of whatever the caller put there.
    # @api private
    INSTRUCTIONS = {instructions: true}.freeze
    private_constant :INSTRUCTIONS

    ##
    # Ugh :)
    # @api private
    FIELDS = %i[record
                name description
                path tool_budget
                retry_budget model
                skills schema
                tracer stream
                tools concurrency
                instructions confirm]
    IVARS  =  %i[record
                 name description
                 path tool_budget
                 tracer concurrency
                 instructions confirm]
    private_constant :FIELDS, :IVARS

    ##
    # @api private
    CASE_PATTERN = /(?<=[a-z])(?=[A-Z])|(?<=[A-Z])(?=[A-Z][a-z])/
    private_constant :CASE_PATTERN

    ##
    # @api private
    File = ::File
    private_constant :File

    ##
    # Returns a provider
    # @return [LLM::Provider]
    attr_reader :llm

    ##
    # Bulk-assign class-level agent defaults from a Hash.
    #
    # Each key is resolved by calling the corresponding class method on the
    # agent subclass. An error is raised for unknown keys so that typos are
    # caught early.
    #
    # @example
    #   class AdminAgent < LLM::Agent
    #     set name: "admin",
    #         instructions: "You are a system administrator",
    #         model: "gpt-4.1-nano",
    #         tools: [LLM::Tool::Exec, LLM::Tool::ReadFile]
    #   end
    #
    # @param [Hash] properties
    # @option properties [String, Symbol, Proc] :name
    # @option properties [String, Symbol, Proc] :description
    # @option properties [String] :instructions
    # @option properties [String] :model
    # @option properties [Array<LLM::Function>] :tools
    # @option properties [Array<String>] :skills
    # @option properties [#to_json] :schema
    # @option properties [Symbol, Array<Symbol>] :concurrency
    # @option properties [LLM::Tracer, Proc] :tracer
    # @option properties [Object, Proc] :stream
    # @option properties [String, Symbol, Array<String, Symbol>, Proc] :confirm
    # @raise [KeyError] when a property key does not match a class-level accessor
    # @return [void]
    def self.set(properties)
      properties.each do
        if respond_to?(_1)
          public_send(_1, _2)
        else
          raise KeyError, "key not found: #{_1}"
        end
      end
    end

    ##
    # Set or get an agent's name
    # @note
    #  This method serves as a self-documenting string
    #  and it is used by {LLM::Console LLM::Console}. It is
    #  optional but recommended.
    # @param [String] name
    #  The agent name
    # @return [String]
    #  Return's the agents name
    def self.name(name = UNDEFINED, &block)
      if name.equal?(UNDEFINED) and block.nil?
        if @name.nil?
          name  = to_s.split("::").last
          @name = name.gsub(CASE_PATTERN, "-").downcase
        else
          @name
        end
      else
        if Class === name
          name  = name.to_s.split("::").last
          @name = name.gsub(CASE_PATTERN, "-").downcase
        else
          @name = block || name
        end
      end
    end

    ##
    # Set or get an agent's description
    # @note
    #  Reading this on the class returns what was configured - a
    #  Symbol or Proc included - because an instance is what
    #  resolves those. Read it on an instance for the description
    #  itself.
    # @note
    #  This method serves as a self-documenting string.
    #  It is optional but recommended.
    # @param [String] desc
    #  The agent's description
    # @return [String, nil]
    #  Returns the agent's description
    def self.description(desc = UNDEFINED, &block)
      if desc.equal?(UNDEFINED) and block.nil?
        @desc
      else
        @desc = block || desc
      end
    end

    ##
    # Set or get the default model
    # @param [String, nil] model
    #  The model identifier
    # @return [String, nil]
    #  Returns the current model when no argument is provided
    def self.model(model = nil, &block)
      return @model if model.nil? and !block
      @model = block || model
    end

    ##
    # Set or get the default schema
    # @param [#to_json, nil] schema
    #  The schema
    # @return [#to_json, nil]
    #  Returns the current schema when no argument is provided
    def self.schema(schema = nil, &block)
      return @schema if schema.nil? and !block
      @schema = block || schema
    end

    ##
    # Set or get the default tools
    # @param [Array<LLM::Function>, nil] tools
    #  One or more tools
    # @return [Array<LLM::Function>]
    #  Returns the current tools when no argument is provided
    def self.tools(*tools, &block)
      return @tools || [] if tools.empty? and !block
      if block
        @tools = block
      elsif single_callable?(tools)
        @tools = tools.first
      else
        @tools = tools.flatten
      end
    end

    ##
    # Set or get the default skills
    # @param [Array<String>, nil] skills
    #  One or more skill directories
    # @return [Array<String>, nil]
    #  Returns the current skills when no argument is provided
    def self.skills(*skills, &block)
      return @skills if skills.empty? and !block
      if block
        @skills = block
      elsif single_callable?(skills)
        @skills = skills.first
      else
        @skills = skills.flatten
      end
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
      return @confirm if tool_names.empty? and !block
      if block
        @confirm = block
      elsif single_callable?(tool_names)
        @confirm = tool_names.first
      else
        @confirm = tool_names.flatten.map(&:to_s)
      end
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
    #  - `:sequential`: sequential calls
    #  - `:thread`: concurrent threads
    #  - `:async`: concurrent async tasks
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
    #     tracer { LLM::Tracer.logger(llm, io: $stdout) }
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
    # Set the file path where an agent's memory
    # can be restored from, and written to.
    # @param [String] path
    #  The path to a file
    # @return [String, nil]
    def self.path(path = UNDEFINED, &block)
      if path.equal?(UNDEFINED) and block.nil?
        @path
      else
        @path = block || path
      end
    end

    ##
    # Set or get the maximum number of tool calls
    # that are allowed in a single turn. Once the
    # budget is spent, no further tool calls are run:
    # we return an in-band message that informs the
    # model it has spent its tool call budget, and
    # keep returning it while the model keeps asking
    # for tools - a model will usually change course
    # afterwards. The budget counts tool calls, so a
    # batch of calls is spent as a batch, and a batch
    # that would take the turn past its budget is not
    # run at all.
    # @note
    #  By default this feature is disabled
    #  (set to `nil`).
    # @param [Integer] budget
    #  The maximum number of tool calls to allow in
    #  a single turn.
    # @return [Integer, nil]
    def self.tool_budget(budget = UNDEFINED, &block)
      if budget.equal?(UNDEFINED) and block.nil?
        @tool_budget
      else
        @tool_budget = block || budget
      end
    end

    ##
    # Sets or returns the retry budget for the agent.
    #
    # The retry budget is the maximum number of times a rate-limited
    # request will be retried before giving up. Each retry sleeps a
    # growing interval, so an exhausted budget surfaces the rate-limit
    # error instead of blocking indefinitely. Enabled (5) by default; a
    # raw {LLM::Context} disables it (0) unless configured.
    # @param [Integer] budget
    #  The maximum number of rate-limit retries in a turn.
    # @return [Integer, nil]
    def self.retry_budget(budget = UNDEFINED)
      if budget.equal?(UNDEFINED)
        @retry_budget.nil? ? UNDEFINED : @retry_budget
      else
        @retry_budget = budget
      end
    end

    ##
    # @api private
    def self.single_callable?(callable)
      callable.size == 1 and (Proc === callable[0] or Symbol === callable[0])
    end
    private_class_method :single_callable?

    ##
    # @param [LLM::Provider] llm
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
      params = {}.merge!(params)
      @llm = llm
      fields, fields_ivar = FIELDS, IVARS
      fields.each do |field|
        resolvable = if params.key?(field)
          params.delete(field)
        else
          (self.class.respond_to?(field) ? self.class.public_send(field) : nil)
        end
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
      ##
      # The provider decides how patient a turn should be: it
      # knows its own API, and how often it recovers from a
      # rate limit rather than failing outright.
      params[:retry_budget] = llm.retry_budget if params[:retry_budget].equal?(UNDEFINED)
      ##
      # The context is bound to the same record the agent holds, so code
      # written against a context alone can find it through `ctx.record`.
      @ctx = LLM::Context.new(llm, params.merge(record: @record).compact)
      @path and File.readable?(@path) ? @ctx.restore(path:) : nil
    end

    ##
    # Returns the agent's name
    # @return [String]
    def name
      @name
    end

    ##
    # Returns a file path where an agent's memory is
    # restored from, and written to after each turn.
    # @return [String, nil]
    def path
      @path
    end

    ##
    # Returns the ORM record this agent is bound to, or nil.
    # @return [Object, nil]
    def record
      @record
    end

    ##
    # Returns the agent's description
    # @return [String, nil]
    def description
      @description
    end

    ##
    # Maintain a conversation via the chat completions API.
    # This method immediately sends a request to the LLM and returns the response.
    #
    # @param prompt (see LLM::Provider#complete)
    # @param [Hash] params The params passed to the provider, including optional :stream, :tools, :schema etc.
    # @option params [Integer] :tool_budget
    #  The maximum number of tool calls that can be made in a single turn
    #  before the agent sends an in-band advisory message that tells the model
    #  it has spent its tool call budget - and usually the model will change
    #  course after that. By default this feature is disabled (set to `nil`).
    # @return [LLM::Response] Returns the LLM's response for this turn.
    # @example
    #   llm = LLM.openai(key: ENV["KEY"])
    #   agent = LLM::Agent.new(llm)
    #   response = agent.talk("Hello, what is your name?")
    #   puts response.choices[0].content
    def talk(prompt, params = {})
      res = run_loop(prompt, params, :talk)
      path ? @ctx.save(path:) : nil
      res
    end

    ##
    # @see LLM::Context#ask
    def ask(prompt, params = {})
      res = run_loop(prompt, params, :ask)
      path ? @ctx.save(path:) : nil
      res
    end

    ##
    # @return [LLM::Buffer<LLM::Message>]
    def messages
      @ctx.messages
    end

    ##
    # Returns a stable id for this agent. The id is borrowed from
    # the context it wraps, so it survives save and restore.
    # @return [String]
    def id
      @ctx.id
    end

    ##
    # Returns the time this agent was created. It is derived
    # from the context id, so it is not persisted separately.
    # @return [Time, nil]
    def created_at
      @ctx.created_at
    end

    ##
    # @return [Integer]
    def retry_budget
      @ctx.retry_budget
    end

    ##
    # @return [Array<LLM::Function>]
    def pending_functions
      @tracer ? @llm.with_tracer(@tracer) { @ctx.pending_functions } : @ctx.pending_functions
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
    # See also: {LLM::Context#token_usage}
    # @return (see LLM::Context#token_usage)
    def token_usage
      @ctx.token_usage
    end
    alias_method :usage, :token_usage

    ##
    # See also: {LLM::Context#context_used}
    # @return (see LLM::Context#context_used)
    def context_used
      @ctx.context_used
    end

    ##
    # See also: {LLM::Context#context_usage}
    # @return (see LLM::Context#context_usage)
    def context_usage
      @ctx.context_usage
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
    # @param [LLM::Tracer, nil] other
    #  A tracer, or nil.
    # @return [void]
    def tracer=(other)
      @ctx.tracer = other
      @tracer = other
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
    # @see LLM::Context#registry
    # @return [LLM::Registry]
    def registry
      @ctx.registry
    end

    ##
    # @see LLM::Context#compacted?
    # @return [Boolean]
    def compacted?
      @ctx.compacted?
    end

    ##
    # Start an agent console that can interact
    # with the agent and its current state. This
    # method requires the following gems to be
    # installed and available to require:
    # 'unicode-display_width', 'kramdown', 'curses',
    # 'test-cmd.rb', and 'xchan.rb'.
    #
    # @note
    #  By default this method disables the tracer for
    #  the duration of the console session, and restores
    #  it afterwards.
    # @param [String] name
    #  The agent's name.
    #  Defaults to {LLM::Agent#name}.
    # @param [String] path
    #  The path to a file where runtime state is read
    #  from, and written to
    # @param [Array<LLM::Tool>] tools
    #  Extra tools to attach for the console session
    # @param [Array<String>] skills
    #  Extra skills to attach for the console session
    # @param [Boolean] tracer
    #  When true, the tracer is kept alive during the
    #  console session. Default is false.
    # @return [void]
    def console(name: self.name, path: nil, tools: [], skills: [], tracer: false, trace: nil)
      if trace != nil
        warn "llm.rb: trace option is deprecated, use tracer instead"
        tracer = trace
      end
      if !tracer
        previous    = self.tracer
        self.tracer = nil
      end
      require_relative "console" unless defined?(::LLM::Console)
      LLM::Console.new(agent: self, name:, path:, tools:, skills:).start
    ensure
      if !tracer
        self.tracer = previous
      end
    end
    alias_method :repl, :console

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
    # @return [LLM::Agent]
    def deserialize(**kw)
      @ctx.deserialize(**kw)
      self
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
    #  Return either `fn.task(strategy).wait` to approve execution or
    #  `fn.cancel(...)` to cancel the call.
    def on_tool_confirmation(fn, strategy)
      fn.cancel
    end

    private

    ##
    # @return [LLM::Prompt]
    def apply_instructions(new_prompt)
      return new_prompt unless @instructions
      ##
      # A prompt that carries a system message of its own is the
      # caller's, and the instructions already in the conversation are
      # left as they are. The context is deliberately not consulted: a
      # restored context always holds the message this exists to bring
      # up to date, which is what `inject_instructions?` tests for.
      refresh_instructions! unless carries_system_message?(new_prompt)
      if LLM::Prompt === new_prompt
        new_prompt.system(@instructions, extra: INSTRUCTIONS) if inject_instructions?(new_prompt)
        new_prompt
      else
        prompt do
          _1.system(@instructions, extra: INSTRUCTIONS) if inject_instructions?
          _1.user(new_prompt)
        end
      end
    end

    ##
    # Brings the instructions stored in the conversation up to date.
    #
    # The message is identified by the mark the agent put on it when it
    # injected it, and not by its role or its position. A role is true
    # of whatever the caller put there - on a provider whose system role
    # is `:user`, the first message of a conversation the caller seeded
    # is a user message too - so a rule written on either of those
    # replaces a message that was never the agent's to replace.
    #
    # A message with no mark is left alone, which is the safe direction:
    # a conversation written before the mark existed keeps its stale
    # instructions rather than losing a message. Stale is recoverable.
    #
    # An agent with no instructions returns first. The caller reaches
    # this through `apply_instructions`, which already returns early for
    # the same reason, and the guard is repeated here so that the method
    # cannot replace a message with nil however it is reached.
    #
    # Comparing content rather than the message is deliberate.
    # {LLM::Message#==} compares everything a message carries apart from
    # its id, which drags fields that have nothing to do with
    # instructions into the comparison. The mark is carried onto the
    # replacement so that the turn after this one can still find it, and
    # so is the role the message already had: it is the provider's, and
    # rebuilding it here would undo the reason the replacement is safe.
    # @api private
    # @return [void]
    def refresh_instructions!
      return unless @instructions
      message = @ctx.messages.first
      return unless message&.extra&.key?(:instructions)
      return if message.content == @instructions
      @ctx.messages.replace(
        [LLM::Message.new(message.role, @instructions, message.extra), *@ctx.messages.drop(1)]
      )
    end

    ##
    # Returns true when a prompt carries a system message of its own.
    #
    # This is the half of `inject_instructions?` that asks about the
    # prompt rather than about the context, and it is the one a refresh
    # needs. The context half says "do not inject again", which is not
    # the same question as "whose instructions are these".
    #
    # The role asked about is the provider's: a prompt's `system` is
    # built with the role the provider gives instructions, which is not
    # the string "system" everywhere.
    # @param [LLM::Prompt, Object] prompt
    # @return [Boolean]
    def carries_system_message?(prompt)
      role = @llm.system_role.to_s
      LLM::Prompt === prompt && prompt.to_a.any? { _1.role.to_s == role }
    end

    ##
    # Returns true when agent instructions should be injected for the turn.
    # Instructions are injected once unless a message with the provider's
    # system role is already present in the existing context or the prompt
    # being sent.
    # @param [LLM::Prompt, nil] prompt
    # @return [Boolean]
    def inject_instructions?(prompt = nil)
      role = @llm.system_role.to_s
      return false if @ctx.messages.any? { _1.role.to_s == role }
      return true if prompt.nil?
      !prompt.to_a.any? { _1.role.to_s == role }
    end

    ##
    # @return [Array<LLM::Function::Return>]
    def call_functions
      strategy = concurrency || :sequential
      return wait(strategy) unless @confirm&.any?
      confirmables = @ctx.pending_functions.select { @confirm.include?(_1.name.to_s) }
      results = confirmables.map { method(:on_tool_confirmation).call(_1, strategy) }
      @ctx.method(:emit_tool_returns).call(confirmables, results)
      if (@ctx.pending_functions - confirmables).any?
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
        max = params.key?(:tool_budget) ? params.delete(:tool_budget) : @tool_budget
        max = Integer(max) if max
        stream = params[:stream] || @ctx.params[:stream]
        params[:stream] = LLM::Stream.try(stream, extra: {concurrency:})
        res = talk.call(apply_instructions(prompt), params)
        spent = 0
        while @ctx.pending_functions?
          batch = @ctx.pending_functions.size
          if max and spent + batch > max
            ##
            # The budget is spent, so the calls are not run.
            # They still have to be answered though: each one
            # gets an in-band return and, just as important,
            # that return is emitted to the stream.
            tools = @ctx.pending_functions
            returns = tools.map(&:budget_spent)
            @ctx.method(:emit_tool_returns).call(tools, returns)
            res = talk.call(returns, params)
          else
            spent += batch if max
            res = talk.call(call_functions, params)
          end
        end
        res
      end
      ##
      # One turn, one trace group. A tracer
      # is told where the turn begins and
      # where it ends. The trace group ID
      # identifies the turn.
      tracer = @tracer || @llm.tracer
      tracer.start_trace(name: "llm.turn", trace_group_id: SecureRandom.uuid_v7)
      ##
      # Where the turn is running, for as long as it runs.
      #
      # A cancel reaches a request in flight and the tools that are
      # running, and between those it reached nothing: the loop is
      # between two requests, or waiting out a retry, or building the
      # next one. What is left over is a raise into the caller the turn
      # is running under, and this names it - recorded here rather than in
      # `Context#talk`, because a turn is a loop and not a request.
      #
      # The scheduler is part of it, and read here rather than by the
      # interrupt: that runs on the canceller's thread, which is not the
      # thread a scheduler was installed on. The fiber strategy names it
      # for the same reason.
      #
      # Taken back below, and that is not a formality: a worker's thread
      # is reused for the turn after this one, and a cancel that arrived
      # late would otherwise land in whatever that thread is doing.
      @ctx.instance_variable_set(
        :@caller,
        LLM::Object.from(
          thread: Thread.current,
          fiber: @llm.request_owner,
          scheduler: Fiber.scheduler
        )
      )
      @llm.with_tracer(tracer, &run)
    ensure
      ##
      # `remove_instance_variable` raises when there is nothing to remove,
      # and a turn can fail above the caller being recorded - `start_trace`
      # is one line of it - so the name is asked for first.
      @ctx.remove_instance_variable(:@caller) if @ctx.instance_variable_defined?(:@caller)
      tracer&.stop_trace
    end

    ##
    # @api private
    def resolve_option(...)
      LLM::Utils.resolve_option(...)
    end
  end
end
