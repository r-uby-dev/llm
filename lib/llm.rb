# frozen_string_literal: true

module LLM
  require "stringio"
  require "securerandom"
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
  require_relative "llm/transport"
  require_relative "llm/response"
  require_relative "llm/mime"
  require_relative "llm/multipart"
  require_relative "llm/file"
  require_relative "llm/pipe"
  require_relative "llm/stream"
  require_relative "llm/provider"
  require_relative "llm/context"
  require_relative "llm/loop_guard"
  require_relative "llm/agent"
  require_relative "llm/buffer"
  require_relative "llm/function"
  require_relative "llm/eventstream"
  require_relative "llm/eventhandler"
  require_relative "llm/tool"
  require_relative "llm/skill"
  require_relative "llm/server_tool"
  require_relative "llm/mcp"
  require_relative "llm/a2a"

  ##
  # Thread-safe monitors for different contexts
  @monitors = {require: Monitor.new, inherited: Monitor.new, registry: Monitor.new, mcp: Monitor.new}

  ##
  # Model registry
  @registry = {}

  ##
  # Requires an optional runtime dependency
  # @raise [LLM::DependencyError]
  #  When the dependency cannot be loaded
  def self.require(name)
    super
  rescue ::LoadError
    names = {"xchan" => "xchan.rb", "net/http/persistent" => "net-http-persistent"}
    name = names[name] || name
    raise LLM::LoadError,
      "#{name} is an optional runtime dependency but it does not appear to be installed. " \
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

  module_function

  ##
  # Returns the JSON adapter used by the library
  # @return [Class]
  #  Returns a class that responds to `dump` and `load`
  def json
    @json ||= JSONAdapter::JSON
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
    when "Yajl", "yajl" then JSONAdapter::Yajl
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

  ##
  # @param (see LLM::Provider#initialize)
  # @return (see LLM::Anthropic#initialize)
  def anthropic(**)
    lock(:require) { require_relative "llm/providers/anthropic" unless defined?(LLM::Anthropic) }
    LLM::Anthropic.new(**)
  end

  ##
  # @param (see LLM::Provider#initialize)
  # @return (see LLM::Google#initialize)
  def google(**)
    lock(:require) { require_relative "llm/providers/google" unless defined?(LLM::Google) }
    LLM::Google.new(**)
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
  def deepseek(**)
    lock(:require) { require_relative "llm/providers/deepseek" unless defined?(LLM::DeepSeek) }
    LLM::DeepSeek.new(**)
  end

  ##
  # @param key (see LLM::Provider#initialize)
  # @return (see LLM::OpenAI#initialize)
  def openai(**)
    lock(:require) { require_relative "llm/providers/openai" unless defined?(LLM::OpenAI) }
    LLM::OpenAI.new(**)
  end

  ##
  # @param (see LLM::Bedrock#initialize)
  # @return (see LLM::Bedrock#initialize)
  def bedrock(**)
    lock(:require) { require_relative "llm/providers/bedrock" unless defined?(LLM::Bedrock) }
    LLM::Bedrock.new(**)
  end

  ##
  # @param key (see LLM::XAI#initialize)
  # @param host (see LLM::XAI#initialize)
  # @return (see LLM::XAI#initialize)
  def xai(**)
    lock(:require) { require_relative "llm/providers/xai" unless defined?(LLM::XAI) }
    LLM::XAI.new(**)
  end

  ##
  # @param key (see LLM::ZAI#initialize)
  # @param host (see LLM::ZAI#initialize)
  # @return (see LLM::ZAI#initialize)
  def zai(**)
    lock(:require) { require_relative "llm/providers/zai" unless defined?(LLM::ZAI) }
    LLM::ZAI.new(**)
  end

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
  # Provides a thread-safe lock
  # @param [Symbol] name The name of the lock
  # @param [Proc] block The block to execute within the lock
  # @return [void]
  def lock(name, &block) = @monitors[name].synchronize(&block)
end
