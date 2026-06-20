# frozen_string_literal: true

##
# The {LLM::A2A} class provides access to agents that implement the
# Agent2Agent (A2A) Protocol. A2A defines a standard way for
# independent AI agents to discover each other's capabilities,
# negotiate interaction modalities, and collaborate on tasks.
#
# In llm.rb, {LLM::A2A} supports both HTTP+JSON/REST and JSON-RPC 2.0
# protocol bindings and focuses on discovering agent skills that can be
# used through {LLM::Context} and {LLM::Agent}.
#
# Requests can be made concurrently and responses are matched by task id.
#
# @example REST binding (default)
#   a2a = LLM::A2A.rest(url: "https://agent.example.com")
#   card = a2a.card
#   puts card.skills.map(&:name)
#   task = a2a.send_message("What is the weather in Tokyo?").task
#   a2a.tasks.get(task.id)
#
# @example JSON-RPC binding
#   a2a = LLM::A2A.jsonrpc(url: "https://agent.example.com")
#
# @example Using skills as tools in a context
#   llm = LLM.openai(key: ENV["KEY"])
#   a2a = LLM::A2A.rest(url: "https://agent.example.com")
#   ctx = LLM::Context.new(llm, tools: a2a.skills)
#   ctx.talk("Analyze this data using the remote agent.")
#   ctx.talk(ctx.wait(:call)) while ctx.functions?
class LLM::A2A
  require_relative "a2a/card"
  require_relative "a2a/error"
  require_relative "a2a/tasks"
  require_relative "a2a/notifications"
  require_relative "a2a/transport/http"

  ##
  # @param [Symbol] binding
  #  The protocol binding to use. One of `:rest` (HTTP+JSON/REST) or
  #  `:jsonrpc` (JSON-RPC 2.0). Defaults to `:rest`.
  # @param [Object] transport
  #  The transport used to communicate with the remote A2A agent
  # @param [String] base_path
  #  Optional base path prefix for REST endpoints
  # @param [String] protocol_version
  #  The expected A2A protocol version. Defaults to `"1.0"`.
  # @return [LLM::A2A]
  def initialize(transport:, binding: :rest, base_path: "", protocol_version: "1.0")
    @binding = binding
    @base_path = LLM::Utils.normalize_base_path(base_path)
    @protocol_version = protocol_version
    @transport = transport
  end

  ##
  # Builds an A2A client over HTTP.
  # @param [String] url
  #  The base URL of the A2A agent (e.g., "https://agent.example.com")
  # @param [Hash<String, String>] headers
  #  Extra HTTP headers to include in requests (e.g., Authorization)
  # @param [Integer, nil] timeout
  #  The timeout in seconds for HTTP requests
  # @param [Boolean] persistent
  #  Whether to use persistent HTTP connections
  # @param [LLM::Transport, Class, Symbol, nil] transport
  #  Optional override with any {LLM::Transport} instance, subclass, or shortcut
  # @param [Symbol] binding
  #  The protocol binding to use. One of `:rest` or `:jsonrpc`
  # @param [String] base_path
  #  Optional base path prefix for REST endpoints
  # @param [String] protocol_version
  #  The expected A2A protocol version. Defaults to `"1.0"`.
  # @return [LLM::A2A]
  def self.http(url:, headers: {}, timeout: 30, persistent: false, transport: nil, binding: :rest, base_path: "", protocol_version: "1.0")
    new(
      binding:,
      base_path:,
      protocol_version:,
      transport: Transport::HTTP.new(
        url:,
        headers:,
        timeout:,
        persistent:,
        transport:,
        protocol_version:
      )
    )
  end

  ##
  # Builds an A2A client over HTTP+JSON/REST.
  # @param [String] url
  # @param [Hash<String, String>] headers
  # @param [Integer, nil] timeout
  # @param [Boolean] persistent
  # @param [LLM::Transport, Class, Symbol, nil] transport
  # @return [LLM::A2A]
  def self.rest(url:, headers: {}, timeout: 30, persistent: false, transport: nil, base_path: "", protocol_version: "1.0")
    http(
      url:,
      headers:,
      timeout:,
      persistent:,
      transport:,
      binding: :rest,
      base_path:,
      protocol_version:
    )
  end

  ##
  # Builds an A2A client over HTTP+JSON with JSON-RPC 2.0.
  # @param [String] url
  # @param [Hash<String, String>] headers
  # @param [Integer, nil] timeout
  # @param [Boolean] persistent
  # @param [LLM::Transport, Class, Symbol, nil] transport
  # @return [LLM::A2A]
  def self.jsonrpc(url:, headers: {}, timeout: 30, persistent: false, transport: nil, base_path: "", protocol_version: "1.0")
    http(
      url:,
      headers:,
      timeout:,
      persistent:,
      transport:,
      binding: :jsonrpc,
      base_path:,
      protocol_version:
    )
  end

  ##
  # Returns the active protocol binding.
  # @return [Symbol]
  attr_reader :binding

  ##
  # Returns the remote agent card.
  #
  # The agent card is fetched from `/.well-known/agent-card.json` and
  # cached for the lifetime of this client instance.
  # @return [LLM::A2A::Card]
  def card
    return @card if defined?(@card)
    @card = LLM::A2A::Card.new(transport.get("/.well-known/agent-card.json"))
  end
  alias_method :agent_card, :card

  ##
  # Returns the agent's skills adapted as callable tools.
  #
  # Each skill in the agent card is mapped to an {LLM::Tool} subclass
  # that wraps a {#send_message} call. When the tool is called, it
  # sends a message to the remote agent and returns the task artifacts
  # as the result.
  # @return [Array<Class<LLM::Tool>>]
  def skills
    @skills ||= card.skills.map { LLM::Tool.a2a(self, _1) }
  end
  alias_method :tools, :skills

  ##
  # Returns task-oriented A2A operations.
  # @return [LLM::A2A::Tasks]
  def tasks
    @tasks ||= LLM::A2A::Tasks.new(self)
  end

  ##
  # Returns push notification configuration operations.
  # @return [LLM::A2A::Notifications]
  def notifications
    @notifications ||= LLM::A2A::Notifications.new(self)
  end

  ##
  # Sends a message to the agent and returns the response.
  # @param [String] text The message text to send
  # @param [Hash] configuration
  #  Optional configuration (accepted_output_modes, return_immediately)
  # @param [Hash, nil] metadata
  #  Optional metadata to attach to the request
  # @return [LLM::Object] The task or message response
  def send_message(text, configuration = {}, metadata: nil)
    body = build_request(
      "SendMessage",
      message: {role: "ROLE_USER", parts: [{text:}], messageId: SecureRandom.uuid},
      configuration:,
      metadata:
    )
    execute_request(body)
  end

  ##
  # Sends a streaming message to the agent.
  #
  # The block is called for each {LLM::Object} event in the stream
  # (Task, Message, TaskStatusUpdateEvent, TaskArtifactUpdateEvent).
  # @param [String] text The message text to send
  # @param [Hash] configuration Optional configuration
  # @yieldparam [LLM::Object] event A stream event
  # @return [void]
  def send_streaming_message(text, configuration = {}, &on_event)
    body = build_request(
      "SendStreamingMessage",
      message: {role: "ROLE_USER", parts: [{text:}], messageId: SecureRandom.uuid},
      configuration:
    )
    execute_stream(body, &on_event)
  end

  ##
  # Gets the current state of a task.
  # @param [String] task_id The task ID to retrieve
  # @param [Integer, nil] history_length
  #  Optional limit on recent messages to include
  # @return [LLM::Object]
  def get_task(task_id, history_length: nil)
    case @binding
    when :rest
      path = rest_path("/tasks/#{task_id}")
      path = "#{path}?historyLength=#{history_length}" if history_length
      res = transport.get(path)
    when :jsonrpc
      body = build_request("GetTask", id: task_id, historyLength: history_length)
      res = transport.post("/", body)
    else
      raise LLM::A2A::Error, "Invalid A2A binding: #{@binding.inspect}"
    end
    LLM::Object.from(res)
  end

  ##
  # Cancels a task in progress.
  # @param [String] task_id The task ID to cancel
  # @param [Hash, nil] metadata Optional metadata to attach to the request
  # @return [LLM::Object]
  def cancel_task(task_id, metadata: nil)
    body = build_request("CancelTask", id: task_id, metadata:)
    case @binding
    when :rest
      res = transport.post(rest_path("/tasks/#{task_id}:cancel"), body)
    when :jsonrpc
      res = transport.post("/", body)
    else
      raise LLM::A2A::Error, "Invalid A2A binding: #{@binding.inspect}"
    end
    LLM::Object.from(res)
  end

  ##
  # Subscribes to streaming updates for an existing task.
  # @param [String] task_id The task ID to subscribe to
  # @yieldparam [LLM::Object] event A stream event
  # @return [void]
  def subscribe_to_task(task_id, &on_event)
    case @binding
    when :rest
      transport.get_stream(rest_path("/tasks/#{task_id}:subscribe")) { on_event&.call(LLM::Object.from(_1)) }
    when :jsonrpc
      body = build_request("SubscribeToTask", id: task_id)
      transport.post_stream("/", body) { on_event&.call(LLM::Object.from(_1)) }
    else
      raise LLM::A2A::Error, "Invalid A2A binding: #{@binding.inspect}"
    end
  end

  ##
  # Lists tasks with optional filtering.
  # @param [String, nil] context_id Optional context ID to filter by
  # @param [String, nil] status Optional task state to filter by
  # @param [Integer, nil] history_length Optional limit on recent messages to include
  # @param [String, nil] status_timestamp_after Optional lower bound for status timestamp filtering
  # @param [Boolean, nil] include_artifacts Whether to include task artifacts
  # @param [Integer] page_size Maximum number of tasks to return
  # @param [String, nil] page_token Pagination cursor
  # @return [LLM::Object]
  def list_tasks(context_id: nil, status: nil, history_length: nil, status_timestamp_after: nil,
                 include_artifacts: nil, page_size: 20, page_token: nil)
    case @binding
    when :rest
      params = {}
      params[:contextId] = context_id if context_id
      params[:status] = status if status
      params[:historyLength] = history_length if history_length
      params[:statusTimestampAfter] = status_timestamp_after if status_timestamp_after
      params[:includeArtifacts] = include_artifacts unless include_artifacts.nil?
      params[:pageSize] = page_size if page_size
      params[:pageToken] = page_token if page_token
      query = URI.encode_www_form(params)
      path = rest_path("/tasks")
      path = "#{path}?#{query}" unless query.empty?
      res = transport.get(path)
    when :jsonrpc
      body = build_request("ListTasks", contextId: context_id, status: status,
                                        historyLength: history_length,
                                        statusTimestampAfter: status_timestamp_after,
                                        includeArtifacts: include_artifacts,
                                        pageSize: page_size, pageToken: page_token)
      res = transport.post("/", body)
    else
      raise LLM::A2A::Error, "Invalid A2A binding: #{@binding.inspect}"
    end
    LLM::Object.from(res)
  end

  ##
  # Creates a push notification configuration for a task.
  # @param [String] task_id The parent task ID
  # @param [String] url The callback URL
  # @param [String, nil] token Optional token to include with notifications
  # @param [Hash, nil] authentication Optional authentication information
  # @param [String, nil] id Optional configuration ID
  # @return [LLM::Object]
  def create_task_push_notification_config(task_id, url:, token: nil, authentication: nil, id: nil)
    body = build_request("CreateTaskPushNotificationConfig", taskId: task_id, url:, token:, authentication:, id:)
    case @binding
    when :rest
      res = transport.post(rest_path("/tasks/#{task_id}/pushNotificationConfigs"), body)
    when :jsonrpc
      res = transport.post("/", body)
    else
      raise LLM::A2A::Error, "Invalid A2A binding: #{@binding.inspect}"
    end
    LLM::Object.from(res)
  end

  ##
  # Retrieves a push notification configuration for a task.
  # @param [String] task_id The parent task ID
  # @param [String] id The configuration ID
  # @return [LLM::Object]
  def get_task_push_notification_config(task_id, id)
    case @binding
    when :rest
      res = transport.get(rest_path("/tasks/#{task_id}/pushNotificationConfigs/#{id}"))
    when :jsonrpc
      body = build_request("GetTaskPushNotificationConfig", taskId: task_id, id:)
      res = transport.post("/", body)
    else
      raise LLM::A2A::Error, "Invalid A2A binding: #{@binding.inspect}"
    end
    LLM::Object.from(res)
  end

  ##
  # Lists push notification configurations for a task.
  # @param [String] task_id The parent task ID
  # @param [Integer, nil] page_size Maximum number of configurations to return
  # @param [String, nil] page_token Pagination cursor
  # @return [LLM::Object]
  def list_task_push_notification_configs(task_id, page_size: nil, page_token: nil)
    case @binding
    when :rest
      params = {}
      params[:pageSize] = page_size if page_size
      params[:pageToken] = page_token if page_token
      query = URI.encode_www_form(params)
      path = rest_path("/tasks/#{task_id}/pushNotificationConfigs")
      path = "#{path}?#{query}" unless query.empty?
      res = transport.get(path)
    when :jsonrpc
      body = build_request("ListTaskPushNotificationConfigs", taskId: task_id, pageSize: page_size, pageToken: page_token)
      res = transport.post("/", body)
    else
      raise LLM::A2A::Error, "Invalid A2A binding: #{@binding.inspect}"
    end
    LLM::Object.from(res)
  end

  ##
  # Deletes a push notification configuration for a task.
  # @param [String] task_id The parent task ID
  # @param [String] id The configuration ID
  # @return [LLM::Object]
  def delete_task_push_notification_config(task_id, id)
    case @binding
    when :rest
      res = transport.delete(rest_path("/tasks/#{task_id}/pushNotificationConfigs/#{id}"))
    when :jsonrpc
      body = build_request("DeleteTaskPushNotificationConfig", taskId: task_id, id:)
      res = transport.post("/", body)
    else
      raise LLM::A2A::Error, "Invalid A2A binding: #{@binding.inspect}"
    end
    LLM::Object.from(res)
  end

  ##
  # Returns the authenticated extended agent card.
  # @return [LLM::A2A::Card]
  def extended_card
    case @binding
    when :rest
      res = transport.get(rest_path("/extendedAgentCard"))
    when :jsonrpc
      body = build_request("GetExtendedAgentCard")
      res = transport.post("/", body)
    else
      raise LLM::A2A::Error, "Invalid A2A binding: #{@binding.inspect}"
    end
    LLM::A2A::Card.new(res)
  end
  alias_method :get_extended_agent_card, :extended_card

  ##
  # @return [String]
  def inspect
    "#<#{LLM::Utils.object_id(self)} @binding=#{@binding.inspect}>"
  end

  private

  attr_reader :transport

  def build_request(method, **params)
    case @binding
    when :rest
      params
    when :jsonrpc
      {jsonrpc: "2.0", method:, params: params.compact, id: SecureRandom.uuid}
    else
      raise LLM::A2A::Error, "Invalid A2A binding: #{@binding.inspect}"
    end
  end

  def execute_request(body)
    res = case @binding
    when :rest
      transport.post(rest_path("/message:send"), body)
    when :jsonrpc
      res = transport.post("/", body)
      if res["error"]
        raise LLM::A2A::Error.new(res["error"]["message"], res["error"]["code"])
      end
      res["result"] || res
    else
      raise LLM::A2A::Error, "Invalid A2A binding: #{@binding.inspect}"
    end
    LLM::Object.from(res)
  end

  def execute_stream(body, &on_event)
    case @binding
    when :rest
      transport.post_stream(rest_path("/message:stream"), body) { on_event&.call(LLM::Object.from(_1)) }
    when :jsonrpc
      transport.post_stream("/", body) { on_event&.call(LLM::Object.from(_1)) }
    else
      raise LLM::A2A::Error, "Invalid A2A binding: #{@binding.inspect}"
    end
  end

  def rest_path(path)
    return path if @base_path.empty?
    "#{@base_path}#{path}"
  end
end
