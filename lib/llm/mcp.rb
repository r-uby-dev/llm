# frozen_string_literal: true

##
# The {LLM::MCP LLM::MCP} class provides access to servers that
# implement the Model Context Protocol. MCP defines a standard way for
# clients and servers to exchange capabilities such as tools, prompts,
# resources, and other structured interactions.
#
# In llm.rb, {LLM::MCP LLM::MCP} currently supports stdio and HTTP
# transports and focuses on discovering tools that can be used through
# {LLM::Context LLM::Context} and {LLM::Agent LLM::Agent}.
#
# An MCP client is stateful. Coordinate lifecycle operations such as
# {#start} and {#stop}; request methods can be issued concurrently and
# responses are matched by JSON-RPC id.
#
# @example stdio transport
#   llm   = LLM.deepseek(key: ENV["KEY"])
#   mcp   = LLM::MCP.stdio(argv: ["npx", "-y", "@forgejo/mcp-server"])
#   agent = LLM::Agent.new(llm)
#
#   # Preferred: session keeps one process alive across multiple calls
#   mcp.session do
#     agent.talk "What's happening on forgejo?", tools: mcp.tools
#   end
#
#   # Also works: one-shot, spawns a new process per call
#   agent.talk "What's happening on forgejo?", tools: mcp.tools
#
# @example HTTP transport
#   mcp = LLM::MCP.http(
#     url: "https://api.githubcopilot.com/mcp/",
#     headers: {"Authorization" => "Bearer #{ENV.fetch('GITHUB_PAT')}"},
#     transport: :net_http_persistent
#   )
#   agent = LLM::Agent.new(llm)
#   agent.talk "What's happening on GitHub?", tools: mcp.tools
class LLM::MCP
  require_relative "mcp/error"
  require_relative "mcp/command"
  require_relative "mcp/mailbox"
  require_relative "mcp/router"
  require_relative "mcp/rpc"
  require_relative "mcp/transport/http"
  require_relative "mcp/transport/stdio"

  include RPC

  ##
  # Builds an MCP client that uses the stdio transport.
  # @param [Hash] stdio
  #  The stdio transport configuration
  # @return [LLM::MCP]
  def self.stdio(**stdio)
    new(stdio:)
  end

  ##
  # Builds an MCP client that uses the HTTP transport.
  # @param [Hash] http
  #  The HTTP transport configuration
  # @return [LLM::MCP]
  def self.http(**http)
    new(http:)
  end

  ##
  # @param [Hash, nil] stdio The configuration for the stdio transport
  # @option stdio [Array<String>] :argv
  #  The command to run for the MCP process
  # @option stdio [Hash] :env
  #  The environment variables to set for the MCP process
  # @option stdio [String, nil] :cwd
  #  The working directory for the MCP process
  # @param [Hash, nil] http The configuration for the HTTP transport
  # @option http [String] :url
  #  The URL for the MCP HTTP endpoint
  # @option http [Hash] :headers
  #  Extra headers for requests
  # @option http [Boolean] :persistent
  #  Whether to use persistent HTTP connections
  # @option http [LLM::Transport, Class, Symbol] :transport
  #  Optional override with any {LLM::Transport} instance, subclass, or
  #  shortcut, similar to {LLM::Provider}
  # @param [Integer] timeout
  #  The maximum amount of time to wait when reading from an MCP process
  # @return [LLM::MCP] A new MCP instance
  def initialize(stdio: nil, http: nil, timeout: 30)
    @timeout = timeout
    @lock = Mutex.new
    @borrowers = 0
    @owned = false
    if stdio and http
      raise ArgumentError, "stdio and http are mutually exclusive"
    elsif stdio
      @stdio   = stdio
      @command = Command.new(**stdio)
      @transport = Transport::Stdio.new(command:)
    elsif http
      @http = http
      @transport = Transport::HTTP.new(**http, timeout:)
    else
      raise ArgumentError, "stdio or http is required"
    end
  end

  ##
  # Starts the MCP process.
  # @return [void]
  def start
    transport.start
    call(transport, "initialize", {clientInfo: {name: "llm.rb", version: LLM::VERSION}})
    call(transport, "notifications/initialized")
  end

  ##
  # Stops the MCP process.
  # @return [void]
  def stop
    transport.stop
    nil
  end

  ##
  # Starts the MCP client for the duration of a block and then stops it.
  # @yield Runs with the MCP client started
  # @raise [LocalJumpError]
  #  When called without a block
  # @raise [StandardError]
  #  Propagates errors raised by {#start}, the block itself, or {#stop}
  # @return [void]
  def run
    @lock.synchronize do
      start
      @owned = false
    end
    yield
  ensure
    stop
  end
  alias_method :session, :run

  ##
  # Returns the tools provided by the MCP process.
  # @return [Array<Class<LLM::Tool>>]
  def tools
    res = with_session { call(transport, "tools/list") }
    res["tools"].map { LLM::Tool.mcp(self, _1) }
  end

  ##
  # Returns the prompts provided by the MCP process.
  # @return [Array<LLM::Object>]
  def prompts
    res = with_session { call(transport, "prompts/list") }
    LLM::Object.from(res["prompts"])
  end

  ##
  # Returns a prompt by name.
  # @param [String] name The prompt name
  # @param [Hash<String, String>, nil] arguments The prompt arguments
  # @return [LLM::Object]
  def find_prompt(name:, arguments: nil)
    params = {name:}
    params[:arguments] = arguments if arguments
    res = with_session { call(transport, "prompts/get", params) }
    res["messages"] = [*res["messages"]].map do |message|
      LLM::Message.new(
        message["role"],
        adapt_content(message["content"]),
        {original_content: message["content"]}
      )
    end
    LLM::Object.from(res)
  end
  alias_method :get_prompt, :find_prompt

  ##
  # Calls a tool by name with the given arguments
  # @param [String] name The name of the tool to call
  # @param [Hash] arguments The arguments to pass to the tool
  # @return [Object] The result of the tool call
  def call_tool(name, arguments = {})
    res = with_session { call(transport, "tools/call", {name:, arguments:}) }
    adapt_tool_result(res)
  end

  ##
  # @return [Hash]
  def to_h
    {timeout:, stdio: @stdio, http: @http}.compact
  end

  private

  attr_reader :command, :transport, :timeout

  ##
  # Borrows the transport for the duration of the block.
  #
  # The first borrower starts the transport, concurrent borrowers reuse
  # it, and the last borrower stops it, so overlapping tool calls never
  # race `start`/`stop` and trip over "MCP transport is not running".
  # An externally started transport is never stopped by a borrower.
  # @yield Runs while the transport is running
  # @return [void]
  def with_session
    @lock.synchronize do
      @borrowers += 1
      unless transport.running?
        start
        @owned = true
      end
    end
    yield
  ensure
    @lock.synchronize do
      @borrowers -= 1
      if @borrowers.zero? and @owned
        @owned = false
        stop
      end
    end
  end

  def adapt_content(content)
    case content
    when String
      content
    when Hash
      content["type"] == "text" ? content["text"].to_s : LLM::Object.from(content)
    when Array
      content.map { adapt_content(_1) }
    else
      content
    end
  end

  def adapt_tool_result(result)
    if result["structuredContent"]
      result["structuredContent"]
    elsif result["content"]
      {content: result["content"]}
    else
      result
    end
  end
end
