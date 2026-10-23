# frozen_string_literal: true

module LLM
  ##
  # Unlike {LLM::Context LLM::Context}
  # the {LLM::Agent LLM::Agent} class
  # automatically manages the tool loop.
  #
  # @example class Agent < LLM::Agent
  #   class Agent < LLM::Agent
  #     set name: "sam altman",
  #         description: "a ceo",
  #         instructions: "beat the competition",
  #         tools: :toolset,
  #         stream: proc { Stream.new(llm) }
  #
  #     private
  #     def toolset
  #       [LLM::Tool::Exec]
  #     end
  #   end
  #
  #   llm   = LLM.openai
  #   agent = Agent.new(llm)
  #   agent.talk("setup ollama to run gpt-oss")
  #
  # @example LLM::Agent.new
  #   llm   = LLM.deepseek
  #   agent = LLM::Agent.new(llm, stream: $stdout)
  #   agent.talk "Hello world"
  #
  # @see LLM::Context The low-level runtime that Agent wraps
  # @see LLM::Tool Tools that Agent can call on your behalf
  # @see LLM::Stream Stream callbacks for model output
  class Agent
    require_relative "agent/interrupt"
    require_relative "agent/registry"

    ##
    # @api private
    UNDEFINED = ::Object.new.freeze
    private_constant :UNDEFINED

    ##
    # @return [Hash]
    # @api private
    INSTRUCTIONS = {instructions: true}.freeze
    private_constant :INSTRUCTIONS

    ##
    # @api private
    FIELDS = %i[record
                name description
                path tool_budget
                retry_budget model
                skills schema
                tracer stream
                compactor compactor_options
                tools concurrency
                instructions confirm
                intercept]
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
    # @return [LLM::Agent::Registry]
    REGISTRY = Registry.new
    private_constant :REGISTRY

    ##
    # Returns a provider
    # @return [LLM::Provider]
    attr_reader :llm

    ##
    # Returns an instance of {LLM::Agent::Registry LLM::Agent::Registry}.
    # @note
    #  The registry holds all _active_
    #  instances of {LLM::Agent LLM::Agent}
    #  and inactive agents are automatically
    #  removed from the registry. The registry
    #  is local to a process, and its children.
    # @return [LLM::Agent::Registry]
    def self.registry
      REGISTRY
    end

    ##
    # Bulk-assign class-level defaults
    #
    # @example
    #   class Agent < LLM::Agent
    #     set name: "007",
    #         description: "a secret agrent",
    #         instructions: "find top secret material",
    #         tools: [LLM::Tool::Exec, LLM::Tool::ReadFile]
    #   end
    #
    # @param [Hash] properties
    # @option properties [String, Symbol, Proc] :name
    # @option properties [String, Symbol, Proc] :description
    # @option properties [String, Symbol, Proc] :instructions
    # @option properties [String, Symbol, Proc] :model
    # @option properties [LLM::Tracer, Symbol, Proc] :tracer
    # @option properties [LLM::Stream, Symbol, Proc] :stream
    # @option properties [Object, Symbol, Proc, nil] :compactor
    # @option properties [Hash, Proc, nil] :compactor_options
    # @option properties [LLM::Schema, Symbol, Proc] :schema
    # @option properties [Array<LLM::Function>, Symbol, Proc] :tools
    # @option properties [Array<String>, Symbol, Proc] :skills
    # @option properties [Symbol, Array<Symbol>] :concurrency
    # @option properties [String, Symbol, Array<String, Symbol>, Proc] :confirm
    # @raise [KeyError]
    #   When a given key does not match a class-level accessor
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
    # Set or get the tool execution concurrency.
    # @param [Symbol, Array<Symbol>, nil] concurrency
    #  Controls how pending tool loops are executed:
    #  - `:sequential`: sequential calls
    #  - `:thread`: concurrent threads
    #  - `:async`: concurrent async tasks
    #  - `:fiber`: concurrent scheduler-backed fibers
    #  - `:fork`: a child process
    #  - `:ractor`: Ruby-based ractors
    # @return [Symbol, Array<Symbol>, nil]
    def self.concurrency(concurrency = UNDEFINED)
      if concurrency.equal?(UNDEFINED)
        @concurrency
      else
        @concurrency = concurrency
      end
    end

    ##
    # Set or get the model an agent will use
    # @param [String, Symbol] model
    #  The model
    # @param [Proc] block
    #  A block that is lazy-evaled.
    # @return [String, nil]
    #  Returns the model
    def self.model(model = UNDEFINED, &block)
     if model.equal?(UNDEFINED) and block.nil?
        @model
      else
        @model = block || model
      end
    end

    ##
    # Set or get an agent's schema
    # @param [LLM::Schema, Symbol] schema
    #  The schema
    # @param [Proc] block
    #  A block that is lazy-evaled.
    # @return [LLM::Schema, nil]
    #  Returns a schema
    def self.schema(schema = UNDEFINED, &block)
     if schema.equal?(UNDEFINED) and block.nil?
        @schema
      else
        @schema = block || schema
      end
    end

    ##
    # Set or get an agent's instructions
    # @param [String, Symbol, nil] instructions
    #  The system instructions
    # @param [Proc] block
    #  A block that is lazy-evaled.
    # @return [String, nil]
    #  Returns the instructions
    def self.instructions(instructions = UNDEFINED, &block)
     if instructions.equal?(UNDEFINED) and block.nil?
        @instructions
      else
        @instructions = block || instructions
      end
    end

    ##
    # Set or get an agent's tracer.
    # @example
    #   class Agent < LLM::Agent
    #     set tracer: proc { LLM::Tracer.logger(llm, io: $stdout) }
    #   end
    # @param [LLM::Tracer, Symbol, nil] tracer
    #  A tracer.
    # @param [Proc] block
    #  A block that is lazy-evaled.
    # @return [LLM::Tracer, Proc, nil]
    def self.tracer(tracer = UNDEFINED, &block)
     if tracer.equal?(UNDEFINED) and block.nil?
        @tracer
      else
        @tracer = block || tracer
      end
    end
    ##
    # Set or get an agent's compactor.
    # @param [Object, Symbol, Proc, nil] compactor
    # @param [Proc] block
    # @return [Object, Symbol, Proc, nil]
    def self.compactor(compactor = UNDEFINED, &block)
      if compactor.equal?(UNDEFINED) and block.nil?
        @compactor
      else
        @compactor = block || compactor
      end
    end

    ##
    # Set or get an agent's compactor options.
    # @param [Hash, Proc, nil] options
    # @param [Proc] block
    # @return [Hash, Proc, nil]
    def self.compactor_options(options = UNDEFINED, &block)
      if options.equal?(UNDEFINED) and block.nil?
        @compactor_options
      else
        @compactor_options = block || options
      end
    end

    ##
    # Set or get an agent's intercept.
    # @param [LLM::Intercept] intercept
    #  An intercept object
    # @param [Proc] block
    #  A block that is lazy-evaled.
    # @return [LLM::Intercept, nil]
    def self.intercept(intercept = UNDEFINED, &block)
     if intercept.equal?(UNDEFINED) and block.nil?
        @intercept
      else
        @intercept = block || intercept
      end
    end

    ##
    # Set or get an agent's stream
    # @example
    #   class Agent < LLM::Agent
    #     set stream: proc { Stream.new }
    #   end
    # @param [Object, Proc, nil] stream
    # @yieldreturn [Object, nil]
    # @return [Object, Proc, nil]
    def self.stream(stream = UNDEFINED, &block)
     if stream.equal?(UNDEFINED) and block.nil?
        @stream
      else
        @stream = block || stream
      end
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
    # an agent can make in a single turn.
    # @note
    #  This feature is disabled by default.
    # @param [Integer] budget
    #  The maximum number of tool calls to allow in
    #  a single turn.
    # @param [Proc] block
    #  A block that is lazy-evaled
    # @return [Integer, nil]
    def self.tool_budget(budget = UNDEFINED, &block)
      if budget.equal?(UNDEFINED) and block.nil?
        @tool_budget
      else
        @tool_budget = block || budget
      end
    end

    ##
    # Set or get the number of attempts an agent
    # will make when given a failed request.
    # @param [Integer] budget
    #  The maximum number of retries in a turn.
    # @param [Proc] block
    #  A block that is lazy-evaled
    # @return [Integer, nil]
    def self.retry_budget(budget = UNDEFINED, &block)
      if budget.equal?(UNDEFINED) and block.nil?
        @retry_budget
      else
        @retry_budget = block || budget
      end
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
    # Set or get the agent tools that require confirmation.
    #
    # @example
    #   class MyAgent < LLM::Agent
    #     confirm :dangerous_tools
    #     private
    #     def dangerous_tools
    #       %w[delete]
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
      if params[:retry_budget].nil?
        params[:retry_budget] = llm.retry_budget
      end
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
    # @see LLM::Context#compactor
    # @return [Class<LLM::Compactor>]
    def compactor
      @ctx.compactor
    end

    ##
    # @see LLM::Context#compactor_options
    # @return [Hash]
    def compactor_options
      @ctx.compactor_options
    end

    ##
    # Start an agent console.
    #
    # @note
    # This method requires the following gems
    # to be installed and available to require:
    # 'unicode-display_width', 'kramdown',
    # 'curses', 'test-cmd.rb', and 'xchan.rb'.
    #
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
    def console(name: self.name, path: nil, tools: [], skills: [], tracer: false)
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
    # the same reason, and the check is repeated here so that the method
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

      begin
        tracer = @tracer || @llm.tracer
        caller = LLM::Object.from(thread: Thread.current,
                                  fiber: @llm.request_owner,
                                  scheduler: Fiber.scheduler).extend(Interrupt)
        @ctx.instance_variable_set(:@caller, caller)
        tracer.start_trace(name: "llm.turn", trace_group_id: SecureRandom.uuid_v7)
        REGISTRY.enter(self)
        @llm.with_tracer(tracer) do
          run.call
        rescue LLM::Interrupt
          tracer&.on_interrupt(scope: :agent)
          raise
        end
      ensure
        REGISTRY.exit(self)
        @ctx.instance_variable_set(:@caller, nil)
        tracer&.stop_trace
      end
    end

    ##
    # @api private
    def resolve_option(...)
      LLM::Utils.resolve_option(...)
    end
  end
end
