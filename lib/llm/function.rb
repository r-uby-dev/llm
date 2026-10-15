# frozen_string_literal: true

##
# The {LLM::Function LLM::Function} class represents a local
# function that can be called by an LLM. Most users should define
# tools as subclasses of {LLM::Tool} instead — Function is the
# lower-level building block that Tool wraps.
#
# @example Tool subclass (preferred for most users)
#   class ReadFile < LLM::Tool
#     name "read-file"
#     description "Read a file from disk"
#     parameter :path, String, "The filename or path"
#     required %i[path]
#
#     def call(path:)
#       {contents: File.read(path)}
#     end
#   end
#
# @example Inline function (block-form DSL)
#   LLM.function(:run_command) do |fn|
#     fn.name "run-command"
#     fn.description "Runs a shell command"
#     fn.params do |schema|
#       schema.object(command: schema.string.required)
#     end
#     fn.define do |command:|
#       {success: Kernel.system(command)}
#     end
#   end
class LLM::Function
  require_relative "function/registry"
  require_relative "function/array"
  require_relative "function/group"
  require_relative "function/sequential/group"
  require_relative "function/task"
  require_relative "function/sequential/task"
  require_relative "function/thread/task"
  require_relative "function/fiber/task"
  require_relative "function/async/reactor"
  require_relative "function/async/task"
  require_relative "function/thread/group"
  require_relative "function/fiber/group"
  require_relative "function/async/group"
  require_relative "function/window"
  require_relative "function/fork"
  require_relative "function/fork/group"
  require_relative "function/ractor"
  require_relative "function/ractor/group"

  extend LLM::Function::Registry

  ##
  # Returns strategies that execute in an isolated environment.
  # @return [Array<Symbol>]
  def self.isolated
    %i[fork ractor]
  end

  ##
  # Tells a runner that its call was interrupted, if it wants telling.
  #
  # Internal to the strategies that run the hook from their own side, where
  # the runner is a local rather than something {#interrupt!} can resolve:
  # the child's copy in `:fork` is not the parent's, and a ractor cannot be
  # handed the function at all. The argument is the runner and not the
  # function, which is what separates this from {#interrupt!}, and one lookup
  # means `on_cancel` keeps its precedence over `on_interrupt` everywhere.
  # @param [Object, nil] runner
  # @return [nil]
  # @api private
  def self.interrupt(runner)
    return nil unless runner
    hook = %i[on_cancel on_interrupt].find { runner.respond_to?(_1) }
    runner.public_send(hook) if hook
    nil
  end

  ##
  # {LLM::Function::Return LLM::Function::Return} represents the result of a
  # tool call.
  #
  # In llm.rb, tool execution is not complete until the requested function is
  # answered with a return object and that return is sent back through the
  # context. This is the object that closes that loop.
  #
  # The return carries:
  # - the tool call ID
  # - the tool name
  # - the tool's return value
  #
  # That value is usually a `Hash`, but it can be any JSON-like structure your
  # tool returns. `LLM::Function#call` produces one automatically, and
  # `LLM::Function#cancel` produces one that represents a cancelled tool call.
  #
  # You can also construct one directly when you need to intercept, scrub, or
  # synthesize a tool return before sending it back to the model.
  #
  # @example Returning a normal tool result
  #   ret = LLM::Function::Return.new("call_1", "weather", {forecast: "sunny"})
  #   ctx.talk(ret)
  #
  # @example Returning a tool result after rewriting its payload
  #   value = ret.value.merge(email: "[REDACTED_EMAIL]")
  #   ctx.talk(LLM::Function::Return.new(ret.id, ret.name, value))
  Return = Struct.new(:id, :name, :value) do
    ##
    # Returns true when the return value represents an error.
    # @return [Boolean]
    def error?
      Hash === value && value[:error] == true
    end

    ##
    # Returns a Hash representation of {LLM::Function::Return}
    # @return [Hash]
    def to_h
      {id:, name:, value:}
    end

    ##
    # @return [String]
    def to_json(...)
      LLM.json.dump(to_h, ...)
    end

    ##
    # @return [nil]
    def interrupt!
      nil
    end
    alias_method :cancel!, :interrupt!
  end

  ##
  # Returns the function ID
  # @return [String, nil]
  attr_accessor :id

  ##
  # Returns function arguments
  # @return [Hash, Array, LLM::Object, nil]
  attr_reader :arguments

  ##
  # Sets function arguments, wrapping them in an LLM::Object
  # @param [Hash, LLM::Object] other
  # @return [void]
  def arguments=(other)
    @arguments = other.nil? ? nil : LLM::Object.from(other)
  end

  ##
  # Compares functions by tool call ID when both sides have one.
  # @param [LLM::Function] other
  # @return [Boolean]
  def ==(other)
    return true if equal?(other)
    return false unless self.class === other
    return false unless id && other.id
    id == other.id
  end
  alias_method :eql?, :==

  ##
  # Returns a hash value compatible with {#==}.
  # @return [Integer]
  def hash
    id ? id.hash : object_id.hash
  end

  ##
  # Returns a tracer, or nil
  # @return [LLM::Tracer, nil]
  attr_accessor :tracer

  ##
  # Returns a model name, or nil
  # @return [String, nil]
  attr_accessor :model

  ##
  # Returns the intercept class that supervises this function, or nil.
  # The context stamps the intercept onto the functions it binds, so any
  # task built from this function checks it before the tool runs.
  # @return [Class<LLM::Intercept>, nil]
  attr_accessor :intercept

  ##
  # @param [String] name The function name
  # @yieldparam [LLM::Function] self The function object
  def initialize(name, &b)
    @name = name
    @schema = LLM::Schema.new
    @called = false
    @cancelled = false
    yield(self) if block_given?
  end

  ##
  # Set (or get) the function name
  # @param [String] name The function name
  # @return [void]
  def name(name = nil)
    if name
      @name = name.to_s
    else
      @name
    end
  end

  ##
  # Set (or get) the function description
  # @param [String] desc The function description
  # @return [void]
  def description(desc = nil)
    if desc
      @description = desc
    else
      @description
    end
  end

  ##
  # Set (or get) the function parameters
  #
  # @note
  #  A parameter type that is given as a proc is resolved when the
  #  parameters are rendered rather than here, so a tool can say
  #  `parameter :fruit, proc { Enum[Fruit.keys] }` and ask the model
  #  for what is available at the time of the call.
  # @yieldparam [LLM::Schema] schema The schema object
  # @return [LLM::Schema::Leaf, nil]
  def params
    if block_given?
      params = yield(@schema)
      params = LLM::Schema.parse(params) if Hash === params
      if @params
        @params.merge!(params)
      else
        @params = params
      end
    else
      @params || LLM::Schema::Object.new({})
    end
  end

  ##
  # Set the function implementation
  # @param [Proc, Class] b The function implementation
  # @return [void]
  def define(klass = nil, &b)
    @runner = klass || b
  end
  alias_method :def, :define

  ##
  # Call the function
  # @return [LLM::Function::Return]
  def call
    llm = @tracer&.llm
    llm ? llm.with_tracer(@tracer) { call_function } : call_function
  ensure
    @called = true
  end

  ##
  # Returns a function as a {LLM::Function::Task LLM::Function::Task}.
  #
  # @example
  #   # As a group
  #   ctx.talk(ctx.pending_functions.wait)
  #
  #   # As a task
  #   task = tool.task(:thread)
  #   result = task.value
  #
  # @note
  #   An in-process strategy resolves the tool here, so a task that has
  #   not been spawned already holds a live instance, and
  #   {LLM::Function::Array#task} builds one for every pending function at
  #   once. A tool that cannot be built carries the same in-band error the
  #   intercept produces rather than raising, so a constructor's failure
  #   answers the model on every strategy.
  # @param [Symbol] strategy
  #   Controls concurrency strategy:
  #   - `:sequential`: Call the function sequentially
  #   - `:thread`: Use threads
  #   - `:async`: Use async tasks (requires async gem)
  #   - `:fork`: Use a forked child process (requires xchan.rb support)
  #   - `:fiber`: Use scheduler-backed fibers (requires Fiber.scheduler)
  #   - `:ractor`: Use Ruby ractors (class-based tools only; MCP tools are not supported)
  #
  # @return [LLM::Function::Task]
  #   Returns a task whose `#value` is an {LLM::Function::Return}.
  def task(strategy, options = {})
    ##
    # Check the function's intercept on the calling thread before handing
    # the tool to the strategy. The task carries the blocked result and
    # returns it without running if the intercept intervenes.
    options = options.merge(intercepted: @intercept&.call(function: self))
    ##
    # Resolve the runner here, on the calling thread, before the task
    # returned below exists for another thread to interrupt.
    #
    # `#interrupt!` resolves the same instance, and `@_runner ||=` is a
    # check-then-create: reached from two threads at once it builds two,
    # runs the call on one and tells the hook on the other.
    #
    # `:async` is in the list because its reactor runs on a background
    # thread, which is the exposure `:thread` has. The cost is that the
    # tool is built on the calling thread rather than inside the reactor,
    # so a tool whose `initialize` wants a current `Async::Task` or a
    # scheduler-installed fiber does not get one.
    #
    # An intercepted task runs nothing, so it resolves nothing. A strategy in
    # {LLM::Function.isolated} stays lazy on purpose, because there the
    # tool is built in the child process or the ractor and this instance
    # is not the one that runs.
    options = options.merge(tracer:, intercepted: options[:intercepted] || resolve(strategy))
    case strategy
    when :sequential
      Sequential::Task.new(self, options)
    when :async
      LLM.require "async" unless defined?(::Async)
      Async::Task.new(self, options)
    when :thread
      Thread::Task.new(self, options)
    when :fiber
      Fiber::Task.new(self, options)
    when :fork
      LLM.require "xchan", "~> 0.24" unless defined?(::Chan::UNIXSocket)
      Fork::Task.new(self, options)
    when :ractor
      raise LLM::RactorError, "Ractor concurrency only supports class-based tools" unless Class === @runner
      if @runner.respond_to?(:skill?) && @runner.skill?
        raise LLM::RactorError, "Ractor concurrency does not support skill-backed tools"
      end
      Ractor::Task.new(self, options.merge(runner_class: @runner, id:, name:, arguments:, model:))
    else
      raise ArgumentError, "Unknown strategy: #{strategy.inspect}. Expected :sequential, :thread, :fiber, :async, :fork, or :ractor"
    end
  end

  ##
  # Returns a value that communicates that the function call was cancelled
  # @example
  #   llm = LLM.openai(key: ENV["KEY"])
  #   ctx = LLM::Context.new(llm, tools: [fn1, fn2])
  #   ctx.talk "I want to run the functions"
  #   ctx.talk ctx.pending_functions.map(&:cancel)
  # @return [LLM::Function::Return]
  def cancel(reason: "function call cancelled", **extra)
    Return.new(id, name, extra.merge(cancelled: true, reason:))
  ensure
    @cancelled = true
  end

  ##
  # Notifies the function runner that the call was interrupted.
  # This is cooperative and only applies to runners that implement
  # `on_cancel` or `on_interrupt`.
  #
  # Resolved through {#runner} rather than read off `@runner`, so that a
  # class-backed tool is told on the object the call will run on. Read off
  # the definition instead, a class answers `respond_to?` with false for
  # both hooks, and a tool that implements one is never told.
  #
  # An in-process strategy has already resolved the runner in {#task}, on
  # the thread that built the task, so this reads a memo rather than
  # creating one. Where there is no tool to tell - one that cannot be
  # built, or a function whose task was never made - this is a no-op
  # rather than a raise, because the call path is where a constructor's
  # failure belongs.
  #
  # Six routes reach the hook, and they differ in where it runs and in
  # whether an interrupt has to have been delivered first:
  #
  # - `:thread`, `:fiber` and `:async` run it on the thread or fiber that ran
  #   the call, once the call has ended, and only where the raise was issued
  #   into a live job.
  # - `:fork` and `:ractor` run it inside the child or the ractor, before the
  #   interrupt is delivered, and only for a message that arrived.
  # - `:sequential` is the exception, and this method is how it is reached:
  #   nothing is raised into a sequential tool, so the hook is its only
  #   notification and it runs on the thread that cancelled, through
  #   {Sequential::Task#interrupt!}.
  #
  # A caller that reaches this directly - `LLM::Context#interrupt!` over
  # pending functions, say - takes the last route, with no delivery to speak
  # of and nothing running.
  # @return [nil]
  def interrupt!
    LLM::Function.interrupt(runner_or_nil)
  end
  alias_method :cancel!, :interrupt!

  ##
  # Returns true when a function has been called
  # @return [Boolean]
  def called?
    @called
  end

  ##
  # Returns true when a function has been cancelled
  # @return [Boolean]
  def cancelled?
    @cancelled
  end

  ##
  # Returns true when this function is backed by a skill tool.
  # @return [Boolean]
  def skill?
    @runner.respond_to?(:skill?) and @runner.skill?
  end

  ##
  # Returns true when a function has neither been called nor cancelled
  # @return [Boolean]
  def pending?
    !@called && !@cancelled
  end

  ##
  # Returns an in-band error for an unresolved function call.
  # @return [LLM::Function::Return]
  def unavailable
    Return.new(id, name, {
      error: true,
      type: LLM::NoSuchToolError.name,
      message: "tool not found"
    })
  end

  ##
  # Returns an in-band error that indicates the tool
  # call budget has been spent.
  # @return [LLM::Function::Return]
  def budget_spent
    cancel(
      reason: "you are making too many tool calls",
      action: ["stop requesting tool calls"],
      advice: ["produce a response from tool calls already made", "temporary error that resets on the next turn"]
    )
  end

  ##
  # Builds an {LLM::Function::Return LLM::Function::Return} for this
  # function, using its own id and name. The given keywords become the
  # return's value.
  # @note
  #   `return` is a Ruby keyword, so this is defined via
  #   Kernel#define_method.
  # @!method return(value)
  #   @param [Hash] value
  #     The return content, eg `{error: true, type: ..., message: ...}`.
  #   @return [LLM::Function::Return]
  define_method(:return) do |value|
    Return.new(id, name, value)
  end

  ##
  # @return [Hash]
  def adapt(provider)
    provider.adapt_function(self)
  end

  ##
  # Returns the bound function runner instance.
  #
  # Resolved once and kept, so that the object an interrupt has to reach is
  # the object that runs the call. A class-backed tool would otherwise build
  # an instance here and discard it, leaving {#interrupt!} with a class to
  # send the hook to.
  #
  # An in-process strategy resolves it in {#task}, on the calling thread,
  # before the task exists for another thread to interrupt. Every other
  # path resolves it at the first call.
  #
  # The tracer is assigned when the instance is resolved, so a tracer set
  # after that does not reach it.
  #
  # The instance belongs to this function object rather than to a call. The
  # per-call copy is the one {LLM::Message#functions} makes, and that is
  # what keeps the usual path to one call per instance; a second {#task} on
  # one function, or a retry, reuses the instance and whatever its ivars
  # hold.
  # @return [Object]
  def runner
    @_runner ||= begin
      _runner = Class === @runner ? @runner.new : @runner
      _runner.tracer = @tracer if _runner.respond_to?(:tracer=)
      _runner
    end
  end

  private

  ##
  # Resolves the runner for a strategy that runs in this process, and
  # answers with an in-band error when the tool cannot be built.
  #
  # {#call_function} resolves inside its own rescue, and that rescue is what
  # answers the model with an error rather than raising into the turn.
  # Resolving earlier keeps that promise by producing the return the intercept
  # would have produced.
  #
  # An interrupt is re-raised rather than answered, which is what
  # {#call_function} does for the same reason: an interrupt is not a tool's
  # failure, and the runner is the thing it is aimed at.
  # @param [Symbol] strategy
  # @return [LLM::Function::Return, nil]
  def resolve(strategy)
    return nil if LLM::Function.isolated.include?(strategy)
    runner
    nil
  rescue LLM::Interrupt
    raise
  rescue => ex
    Return.new(id, name, {error: true, type: ex.class.name, message: ex.message})
  end

  ##
  # The runner, or nil when it cannot be built.
  #
  # An interrupt has nothing to tell if there is no tool to tell, and a
  # cancel is the wrong place to raise a constructor's failure, which the
  # call path answers in-band.
  # @return [Object, nil]
  def runner_or_nil
    runner
  rescue StandardError
    nil
  end

  ##
  # A duplicate resolves its own runner.
  #
  # The copy a task runs belongs to one call, and the instance that call
  # resolves belongs to that copy - never to the definition it was
  # duplicated from, which is shared and globally registered.
  # @param [LLM::Function] other
  # @return [void]
  def initialize_copy(other)
    super
    @_runner = nil
  end

  ##
  # Internal method that calls the function and returns a Return object.
  # Handles both class-based and proc-based runners, and rescues exceptions.
  #
  # @return [LLM::Function::Return]
  #   Returns a Return object with either the function result or error information.
  def call_function
    runner = self.runner
    kwargs = arguments.respond_to?(:to_h) ? arguments.to_h.transform_keys(&:to_sym) : arguments
    Return.new(id, name, runner.call(**kwargs))
  rescue LLM::Interrupt
    raise
  rescue => ex
    Return.new(id, name, {error: true, type: ex.class.name, message: ex.message})
  end
end
