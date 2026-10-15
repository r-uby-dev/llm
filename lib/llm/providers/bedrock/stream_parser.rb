# frozen_string_literal: true

class LLM::Bedrock
  ##
  # Parses Bedrock Converse Stream events into a response body
  # and emits stream callbacks (on_content, on_tool_call, etc.).
  #
  # Receives decoded JSON payloads from {StreamDecoder} along with
  # the AWS Event Stream event type header.
  #
  # Bedrock Converse Stream event types:
  #   messageStart — initial role
  #   contentBlockStart — tool use or reasoning start
  #   contentBlockDelta — text delta, tool input JSON, or reasoning text
  #   contentBlockStop — content block finished
  #   messageStop — final stop reason, usage metadata
  #
  # @api private
  class StreamParser
    TOOL_MARKER = "<｜DSML｜function_calls"

    ##
    # @return [Hash] Fully constructed response body
    attr_reader :body

    ##
    # @param [LLM::Stream] stream
    def initialize(stream)
      @body = {"output" => {"message" => {"role" => "assistant", "content" => []}}}
      @stream = stream
      @text_markers = {}
    end

    ##
    # @param [Hash] payload Decoded JSON from an event stream frame
    # @param [String, nil] event_type The :event-type header value
    # @return [self]
    def parse!(payload, event_type: nil)
      type = event_type || payload["type"]
      case type
      when "messageStart"
        # { "role" => "assistant" }
      when "contentBlockStart"
        # { "contentBlockIndex" => 0, "start" => { "toolUse" => {...} } }
        handle_content_block_start(payload)
      when "contentBlockDelta"
        # { "contentBlockIndex" => 0, "delta" => { "text" => "..." } }
        handle_content_block_delta(payload)
      when "contentBlockStop"
        handle_content_block_stop(payload)
      when "messageStop"
        # { "stopReason" => "end_turn", "metadata" => {"usage" => {...}} }
        merge_metadata(payload)
      when "metadata"
        # { "usage" => {...} }
        merge_metadata(payload)
      end
      self
    end

    ##
    # @return [void]
    def free
      @text_markers.clear
    end

    private

    def handle_content_block_start(payload)
      index = payload["contentBlockIndex"]
      start_data = payload["start"] || {}
      if (tool_use = start_data["toolUse"])
        content[index] = {"toolUse" => {"toolUseId" => tool_use["toolUseId"], "name" => tool_use["name"], "input" => +""}}
      elsif (reasoning = start_data["reasoningContent"])
        content[index] = {"reasoningContent" => {"text" => +"", "signature" => reasoning["signature"]}.compact}
      end
    end

    def handle_content_block_delta(payload)
      index = payload["contentBlockIndex"]
      delta = payload["delta"] || {}
      if (text = delta["text"])
        ensure_content_block(index, "text")
        visible = filtered_text(index, text)
        return if visible.empty?
        content[index]["text"] ||= +""
        content[index]["text"] << visible
        emit_content(visible)
      elsif (tool_input = delta.dig("toolUse", "input"))
        ensure_content_block(index, "tool_use")
        content[index]["toolUse"]["input"] ||= +""
        content[index]["toolUse"]["input"] << tool_input
      elsif (reasoning = delta["reasoningContent"])
        ensure_content_block(index, "reasoning")
        if reasoning["text"]
          content[index]["reasoningContent"]["text"] ||= +""
          content[index]["reasoningContent"]["text"] << reasoning["text"]
          emit_reasoning_content(reasoning["text"])
        end
        if reasoning["signature"]
          content[index]["reasoningContent"]["signature"] = reasoning["signature"]
        end
      end
    end

    def handle_content_block_stop(payload)
      index = payload["contentBlockIndex"]
      item = content[index]
      return unless item
      flush_text(index, item)
      if item["toolUse"] && item["toolUse"]["input"].is_a?(String)
        parsed = LLM.json.load(item["toolUse"]["input"])
        item["toolUse"]["input"] = parsed.is_a?(Hash) ? parsed : {}
        emit_tool(item)
      end
    rescue *LLM.json.parser_error
      item["toolUse"]["input"] = {} if item&.dig("toolUse")
    end

    def ensure_content_block(index, type)
      content[index] ||= case type
      when "tool_use" then {"toolUse" => {"input" => +""}}
      when "reasoning" then {"reasoningContent" => {"text" => +""}}
      else {}
      end
    end

    def filtered_text(index, text)
      state = (@text_markers[index] ||= +"")
      value = state << text
      value.gsub!(TOOL_MARKER, "")
      keep = marker_prefix_length(value)
      @text_markers[index] = keep.zero? ? +"" : value[-keep..]
      keep.zero? ? value : value[0...-keep]
    end

    def flush_text(index, item)
      value = @text_markers.delete(index).to_s
      return unless item["text"]
      if value.empty?
        content[index] = {} if item["text"].empty?
      else
        item["text"] << value
        emit_content(value)
      end
    end

    def marker_prefix_length(value)
      [value.length, TOOL_MARKER.length - 1].min.downto(1) do |length|
        return length if TOOL_MARKER.start_with?(value[-length..])
      end
      0
    end

    def merge_metadata(payload)
      metadata = payload["metadata"] || payload
      return unless metadata.is_a?(Hash)
      usage = metadata["usage"]
      @body["usage"] = usage if usage
      @body["stopReason"] = payload["stopReason"] if payload["stopReason"]
    end

    def emit_content(value)
      @stream.on_content(value)
    end

    def emit_reasoning_content(value)
      @stream.on_reasoning_content(value)
    end

    def emit_tool(tool)
      function, error = resolve_tool(tool)
      error ? @stream.queue << error : @stream.on_tool_call(function)
    end

    def resolve_tool(tool)
      payload = tool["toolUse"] || {}
      registered = @stream.__find__(payload["name"])
      fn = (registered || LLM::Function.new(payload["name"])).dup.tap do |f|
        f.id = payload["toolUseId"]
        f.arguments = payload["input"] || {}
        f.tracer = @stream.extra[:tracer]
        f.model = @stream.extra[:model]
        f.intercept = @stream.extra[:intercept]
      end
      [fn, registered ? nil : fn.unavailable]
    end

    def content
      @body["output"]["message"]["content"]
    end
  end
end
