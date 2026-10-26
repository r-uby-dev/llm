#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require "socket"

module LLM::MCPServer
  ECHO_TOOL = {
    "name" => "echo",
    "description" => "Echoes text",
    "inputSchema" => {
      "type" => "object",
      "properties" => {"text" => {"type" => "string"}},
      "required" => ["text"]
    }
  }.freeze

  ##
  # @param [Hash] message
  # @return [Hash]
  def self.reply(message)
    case message["method"]
    when "initialize"
      result = {
        "protocolVersion" => "2024-11-05",
        "capabilities" => {"tools" => {}},
        "serverInfo" => {"name" => "mcp-stub", "version" => "1.0"}
      }
    when "tools/list"
      result = {"tools" => [ECHO_TOOL]}
    when "tools/call"
      text = message.dig("params", "arguments", "text")
      result = {"structuredContent" => {"message" => "echo: #{text}"}}
    else
      return {jsonrpc: "2.0", id: message["id"], error: {code: -32601, message: "unknown method"}}
    end
    {jsonrpc: "2.0", id: message["id"], result:}
  end

  ##
  # @param [String] line
  #  One JSON-RPC message
  # @return [String, nil]
  #  The reply, or nil for a notification
  def self.handle(line)
    message = JSON.parse(line)
    return nil if message["id"].nil?
    reply(message).to_json
  end

  ##
  # @return [void]
  def self.stdio
    $stdin.each_line do |line|
      response = handle(line)
      next unless response
      $stdout.puts(response)
      $stdout.flush
    end
  end

  ##
  # @param [Integer] port
  # @return [void]
  def self.http(port)
    server = TCPServer.new("127.0.0.1", port)
    loop do
      Thread.new(server.accept) do |sock|
        sock.gets
        headers = {}
        while (line = sock.gets) && line != "\r\n"
          key, value = line.split(": ", 2)
          headers[key.downcase] = value.to_s.chomp
        end
        response = handle(sock.read(headers["content-length"].to_i))
        event = response ? "data: #{response}\n\n" : ""
        sock.print("HTTP/1.1 200 OK\r\nContent-Type: text/event-stream\r\n" \
                   "Content-Length: #{event.bytesize}\r\nConnection: close\r\n\r\n#{event}")
        sock.close
      end
    end
  end
end

if $0 == __FILE__
  case ARGV[0]
  when "--http" then LLM::MCPServer.http(Integer(ARGV[1]))
  when "--stdio", nil then LLM::MCPServer.stdio
  end
end
