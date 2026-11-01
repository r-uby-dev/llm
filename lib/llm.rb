# frozen_string_literal: true

##
# An agentic runtime.
#
# @example LLM::Agent
#   require "llm"
#   llm   = LLM.deepseek                             # 1. pick a provider
#   agent = LLM::Agent.new(llm, stream: $stdout)     # 2. create an agent
#   agent.talk "Hello world"                         # 3. talk to it
#
# @see LLM::Agent The recommended high-level interface
# @see LLM::Context The low-level stateful runtime (advanced)
module LLM
  extend self

  begin
    old = Warning[:experimental]
    Warning[:experimental] = false
    (Ractor.new{}.value)
  ensure
    Warning[:experimental] = old
  end

  require "stringio"
  require "securerandom"
  require "time"
  require_relative "llm/lock"
  require_relative "llm/compactor"
  require_relative "llm/message_filter"
  require_relative "llm/json_adapter"
  require_relative "llm/tracer"
  require_relative "llm/error"
  require_relative "llm/contract"
  require_relative "llm/registry"
  require_relative "llm/cost"
  require_relative "llm/usage"
  require_relative "llm/prompt"
  require_relative "llm/schema"
  require_relative "llm/object"
  require_relative "llm/utils"
  require_relative "llm/model"
  require_relative "llm/version"
  require_relative "llm/message"
  require_relative "llm/request_adapter"
  require_relative "llm/transport"
  require_relative "llm/response"
  require_relative "llm/mime"
  require_relative "llm/multipart"
  require_relative "llm/file"
  require_relative "llm/pipe"
  require_relative "llm/stream"
  require_relative "llm/provider"
  require_relative "llm/context"
  require_relative "llm/intercept"
  require_relative "llm/agent"
  require_relative "llm/buffer"
  require_relative "llm/function"
  require_relative "llm/eventstream"
  require_relative "llm/eventhandler"
  require_relative "llm/tool"
  require_relative "llm/server_tool"
  require_relative "llm/mcp"
  require_relative "llm/a2a"
  require_relative "llm/uridata"

  ##
  # @api private
  UNDEFINED = ::Object.new.freeze

  ##
  # Model registry
  @registry = {}

  ##
  # @param [Hash] opts
  #  MCP client options
  # @option opts [Hash, nil] :stdio
  #  Standard I/O transport options
  # @option opts [Array<String>] :stdio/:argv
  #  The command to run for the MCP process
  # @option opts [Hash] :stdio/:env
  #  The environment variables to set for the MCP process
  # @option opts [String, nil] :stdio/:cwd
  #  The working directory for the MCP process
  # @return [LLM::MCP]
  def mcp(**opts)
    LLM::MCP.new(**opts)
  end

  ##
  # Creates a new A2A client connected to a remote agent.
  #
  # @param [Hash, nil] http
  # @option http [String] :url
  #  The base URL of the A2A agent (e.g., "https://agent.example.com")
  # @option http [Hash<String, String>] :headers
  #  Extra HTTP headers (e.g., Authorization)
  # @option http [Integer, nil] :timeout
  #  Request timeout in seconds
  # @option http [LLM::Transport, Class, nil] :transport
  #  Optional transport override
  # @param [Symbol] binding
  #  The protocol binding to use. One of `:rest` or `:jsonrpc`
  # @return [LLM::A2A]
  def a2a(http:, binding: :rest)
    LLM::A2A.http(**http, binding:)
  end

  ##
  # Define a function
  # @example
  #   LLM.function(:system) do |fn|
  #     fn.description "Run system command"
  #     fn.params do |schema|
  #       schema.object(command: schema.string.required)
  #     end
  #     fn.define do |command:|
  #       system(command)
  #     end
  #   end
  # @param [Symbol] key The function name / key
  # @param [Proc] b The block to define the function
  # @return [LLM::Function] The function object
  def function(key, &b)
    LLM::Function.new(key, &b)
  end

  ##
  # Interrupt an agent.
  # @see LLM::Agent::Registry
  # @param [LLM::Agent, nil] agent
  # @param [String, Integer, nil] id
  # @param [Integer] attempts
  # @param [Numeric] interval
  # @return [LLM::Agent, false]
  #  The agent that was interrupted, or false
  def interrupt(agent: nil, id: nil, attempts: 1, interval: 0.1)
    attempts.times do |count|
      record = LLM::Agent.registry.find(agent:, id:)
      if record
        record.interrupt!
        return record
      else
        break if (count+1) == attempts
        sleep(interval)
      end
    end
    false
  end

  ##
  # Logs a debug message to `$stderr`
  # @note
  #  This method is a noop when the
  #  {LLM.debug_mode:} method returns
  #  false and when the $LLMRB_DEBUG
  #  variable is not set.
  # @param [String] msg
  # @param [IO] io
  #  An optional IO
  # @return [void]
  def self.debug(msg, io = debug_io)
    return unless @debug_mode || ENV["LLMRB_DEBUG_MODE"] == "1"
    log = -> do
      io.puts sprintf("runtime             llm.rb "    \
                      "\n"                             \
                      "runtime.version     %s"         \
                      "\n"                             \
                      "runtime.message     #{msg}"     \
                      "\n"                             \
                      "runtime.info"                   \
                      "\n"                             \
                      "  time.now            %s"       \
                      "\n"                             \
                      "  ractor.main         %s"       \
                      "\n"                             \
                      "  ractor.count        %s"       \
                      "\n"                             \
                      "\n",
                      LLM::VERSION.to_s,
                      Time.now.utc.to_s,
                      Ractor.main? ? "yes" : "no",
                      Ractor.count.to_s)
    end
    lock(:debug, &log)
  end

  ##
  # @note
  #  Defaults to $stderr.
  # @param [IO] io
  #  An IO or file that {.debug} writes to.
  # @return [void]
  def self.debug_io=(io)
    @io = io
  end

  ##
  # The IO used by the {.debug} method.
  # Defaults to $stderr.
  # @return [IO]
  def self.debug_io
    @io || $stderr
  end

  ##
  # Toggles debug mode
  # @return [void]
  def self.debug_mode!
    @debug_mode = !@debug_mode
  end

  ##
  # Are we in debug mode?
  # @return [Boolean]
  def self.debug_mode?
    !!@debug_mode
  end

  ##
  # Requires an optional runtime dependency
  # @param [String] name
  #  The name of a gem
  # @param [String, nil] version
  #  Optional gem version
  # @raise [LLM::LoadError]
  #  When the dependency cannot be loaded
  def self.require(name, version = nil)
    names = {"xchan" => "xchan.rb",
              "net/http/persistent" => "net-http-persistent",
              "unicode/display_width" => "unicode-display_width"}
    gem(names[name] || name, version) if version
    super(name)
  rescue ::LoadError
    name = names[name] || name
    raise LLM::LoadError,
      "#{name}#{version ? " #{version}" : ""} is an optional " \
      "runtime dependency but it does not appear to be installed. " \
      "Consider 'gem install #{name}', adding '#{name}' to your Gemfile or " \
      "opting out of the functionality provided by '#{name}'"
  end

  ##
  # @param [Symbol, LLM::Provider] llm
  #  The name of a provider, or an instance of LLM::Provider
  # @return [LLM::Object]
  def self.registry_for(llm)
    lock(:registry) do
      name = Symbol === llm ? llm : llm.name
      @registry[name] ||= Registry.for(name)
    end
  end

  ##
  # Returns the JSON adapter used by the library
  # @return [Class]
  #  Returns a class that responds to `dump` and `load`
  def json
    @json
  end

  ##
  # Sets the JSON adapter used by the library
  # @note
  #  This should be set once from the main thread when your program starts.
  #  Defaults to {LLM::JSONAdapter::JSON LLM::JSONAdapter::JSON}.
  # @param [Class, String, Symbol] adapter
  #  A JSON adapter class or its name
  # @return [void]
  def json=(adapter)
    @json = case adapter.to_s
    when "JSON", "json" then JSONAdapter::JSON
    when "Oj", "oj" then JSONAdapter::Oj
    else
      is_class = Class === adapter
      is_subclass = is_class && adapter.ancestors.include?(LLM::JSONAdapter)
      if is_subclass
        adapter
      else
        raise TypeError, "Adapter must be a subclass of LLM::JSONAdapter"
      end
    end
  end
  self.json = "json"

  ##
  # @param (see LLM::Provider#initialize)
  # @return (see LLM::Anthropic#initialize)
  def anthropic(key: UNDEFINED, **)
    lock(:require) { require_relative "llm/providers/anthropic" unless defined?(LLM::Anthropic) }
    if key == UNDEFINED
      LLM::Anthropic.new(key: key(name: __method__), **)
    else
      LLM::Anthropic.new(key:, **)
    end
  end

  ##
  # @param (see LLM::Provider#initialize)
  # @return (see LLM::Google#initialize)
  def google(key: UNDEFINED, **)
    lock(:require) { require_relative "llm/providers/google" unless defined?(LLM::Google) }
    if key == UNDEFINED
      LLM::Google.new(key: key(name: __method__), **)
    else
      LLM::Google.new(key:, **)
    end
  end

  ##
  # @param key (see LLM::Provider#initialize)
  # @return (see LLM::Ollama#initialize)
  def ollama(key: nil, **)
    lock(:require) { require_relative "llm/providers/ollama" unless defined?(LLM::Ollama) }
    LLM::Ollama.new(key:, **)
  end

  ##
  # @param key (see LLM::Provider#initialize)
  # @return (see LLM::LlamaCpp#initialize)
  def llamacpp(key: nil, **)
    lock(:require) { require_relative "llm/providers/llamacpp" unless defined?(LLM::LlamaCpp) }
    LLM::LlamaCpp.new(key:, **)
  end

  ##
  # @param key (see LLM::Provider#initialize)
  # @return (see LLM::DeepSeek#initialize)
  def deepseek(key: UNDEFINED, **)
    lock(:require) { require_relative "llm/providers/deepseek" unless defined?(LLM::DeepSeek) }
    if key == UNDEFINED
      LLM::DeepSeek.new(key: key(name: __method__), **)
    else
      LLM::DeepSeek.new(key:, **)
    end
  end

  ##
  # @param key (see LLM::Provider#initialize)
  # @return (see LLM::Hanzo#initialize)
  def hanzo(key: UNDEFINED, **)
    lock(:require) { require_relative "llm/providers/hanzo" unless defined?(LLM::Hanzo) }
    if key == UNDEFINED
      LLM::Hanzo.new(key: key(name: __method__), **)
    else
      LLM::Hanzo.new(key:, **)
    end
  end

  ##
  # @param key (see LLM::Provider#initialize)
  # @return (see LLM::OpenAI#initialize)
  def openai(key: UNDEFINED, **)
    lock(:require) { require_relative "llm/providers/openai" unless defined?(LLM::OpenAI) }
    if key == UNDEFINED
      LLM::OpenAI.new(key: key(name: __method__), **)
    else
      LLM::OpenAI.new(key:, **)
    end
  end

  ##
  # @param key (see LLM::Provider#initialize)
  # @return (see LLM::DeepInfra#initialize)
  def deepinfra(key: UNDEFINED, **)
    lock(:require) { require_relative "llm/providers/deepinfra" unless defined?(LLM::DeepInfra) }
    if key == UNDEFINED
      LLM::DeepInfra.new(key: key(name: __method__), **)
    else
      LLM::DeepInfra.new(key:, **)
    end
  end

  ##
  # @param key (see LLM::XAI#initialize)
  # @param host (see LLM::XAI#initialize)
  # @return (see LLM::XAI#initialize)
  def xai(key: UNDEFINED, **)
    lock(:require) { require_relative "llm/providers/xai" unless defined?(LLM::XAI) }
    if key == UNDEFINED
      LLM::XAI.new(key: key(name: __method__), **)
    else
      LLM::XAI.new(key:, **)
    end
  end

  ##
  # @param key (see LLM::Mistral#initialize)
  # @param host (see LLM::Mistral#initialize)
  # @return (see LLM::Mistral#initialize)
  def mistral(key: UNDEFINED, **)
    lock(:require) { require_relative "llm/providers/mistral" unless defined?(LLM::Mistral) }
    if key == UNDEFINED
      LLM::Mistral.new(key: key(name: __method__), **)
    else
      LLM::Mistral.new(key:, **)
    end
  end

  ##
  # @param key (see LLM::ZAI#initialize)
  # @param host (see LLM::ZAI#initialize)
  # @return (see LLM::ZAI#initialize)
  def zai(key: UNDEFINED, **)
    lock(:require) { require_relative "llm/providers/zai" unless defined?(LLM::ZAI) }
    if key == UNDEFINED
      LLM::ZAI.new(key: key(name: __method__), **)
    else
      LLM::ZAI.new(key:, **)
    end
  end

  ##
  # @param key (see LLM::Moonshot#initialize)
  # @param host (see LLM::Moonshot#initialize)
  # @return (see LLM::Moonshot#initialize)
  def moonshot(key: UNDEFINED, **)
    lock(:require) { require_relative "llm/providers/moonshot" unless defined?(LLM::Moonshot) }
    if key == UNDEFINED
      LLM::Moonshot.new(key: key(name: __method__), **)
    else
      LLM::Moonshot.new(key:, **)
    end
  end

  ##
  # @param key (see LLM::OpenRouter#initialize)
  # @param host (see LLM::OpenRouter#initialize)
  # @return (see LLM::OpenRouter#initialize)
  def openrouter(key: UNDEFINED, **)
    lock(:require) { require_relative "llm/providers/openrouter" unless defined?(LLM::OpenRouter) }
    if key == UNDEFINED
      LLM::OpenRouter.new(key: key(name: __method__), **)
    else
      LLM::OpenRouter.new(key:, **)
    end
  end

  ##
  # @param key (see LLM::Alibaba#initialize)
  # @param host (see LLM::Alibaba#initialize)
  # @return (see LLM::Alibaba#initialize)
  def alibaba(key: UNDEFINED, **)
    lock(:require) { require_relative "llm/providers/alibaba" unless defined?(LLM::Alibaba) }
    if key == UNDEFINED
      LLM::Alibaba.new(key: key(name: :alibaba), **)
    else
      LLM::Alibaba.new(key:, **)
    end
  end
  alias_method :aliyun, :alibaba

  ##
  # @param (see LLM::Bedrock#initialize)
  # @return (see LLM::Bedrock#initialize)
  def bedrock(access_key_id: UNDEFINED, secret_access_key: UNDEFINED, region: UNDEFINED, **)
    lock(:require) { require_relative "llm/providers/bedrock" unless defined?(LLM::Bedrock) }
    if [access_key_id, secret_access_key, region].any? { _1 == UNDEFINED }
      access_key_id = ENV["AWS_ACCESS_KEY_ID"] if access_key_id == UNDEFINED
      secret_access_key = ENV["AWS_SECRET_ACCESS_KEY"] if secret_access_key == UNDEFINED
      region = ENV["AWS_REGION"] if region == UNDEFINED
      if access_key_id.to_s.strip.empty? || secret_access_key.to_s.strip.empty?
        raise ArgumentError, "you must provide an API key"
      end
      LLM::Bedrock.new(access_key_id:, secret_access_key:, region:, **)
    else
      LLM::Bedrock.new(access_key_id:, secret_access_key:, region:, **)
    end
  end

  ##
  # @api private
  def self.lock(name, &b)
    LLM::Lock.synchronize(name, &b)
  end

  private

  ##
  # Resolves a provider's API key from the environment.
  # @param [Symbol] name
  #  The provider name.
  # @raise [ArgumentError]
  #  When no registered env var is set.
  # @return [String]
  def key(name:)
    registry = LLM::Registry.for(name)
    keyname  = registry.env.find { ENV.key?(_1) }
    if keyname.nil?
      keyname = registry.env.first
      raise ArgumentError, "an api key is required - " \
                           "did you forget to set $#{keyname}?"
    end
    ENV[keyname]
  end
end
