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
  require_relative "function/tracing"
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
  require_relative "function/fork"
  require_relative "function/fork/group"
  require_relative "function/ractor"
  require_relative "function/ractor/group"

  extend LLM::Function::Registry
  prepend LLM::Function::Tracing

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
  # Returns the guard class that protects this function, or nil.
  # The context stamps the guard onto the functions it binds, so any task
  # built from this function checks it before the tool runs.
  # @return [Class<LLM::Guard>, nil]
  attr_accessor :guard

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
    # Check the function's guard on the calling thread before handing
    # the tool to the strategy. The task carries the blocked result and
    # returns it without running if the guard intervenes.
    options = options.merge(guarded: @guard&.call(function: self))
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
      LLM.require "xchan", "~> 0.23" unless defined?(::Chan::UNIXSocket)
      Fork::Task.new(self, options.merge(tracer: @tracer))
    when :ractor
      raise LLM::RactorError, "Ractor concurrency only supports class-based tools" unless Class === @runner
      if @runner.respond_to?(:skill?) && @runner.skill?
        raise LLM::RactorError, "Ractor concurrency does not support skill-backed tools"
      end
      Ractor::Task.new(self, options.merge(runner_class: @runner, id:, name:, arguments:, tracer: @tracer, model:))
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
  def cancel(reason: "function call cancelled")
    Return.new(id, name, {cancelled: true, reason:})
  ensure
    @cancelled = true
  end

  ##
  # Notifies the function runner that the call was interrupted.
  # This is cooperative and only applies to runners that implement
  # `on_interrupt`.
  # @return [nil]
  def interrupt!
    hook = %i[on_cancel on_interrupt].find { @runner.respond_to?(_1) }
    @runner.public_send(hook) if hook
    nil
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
    LLM::Function::Return.new(id, name, {
      error: true,
      type: "LLM::BudgetSpentError",
      message: "the tool call budget for this turn has been spent. " \
               "try to solve the problem with less tool calls."
    })
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
  # @return [Object]
  def runner
    runner = Class === @runner ? @runner.new : @runner
    runner.tracer = @tracer if runner.respond_to?(:tracer=)
    runner
  end

  private

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
