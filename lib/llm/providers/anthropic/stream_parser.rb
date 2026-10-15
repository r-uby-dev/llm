# frozen_string_literal: true

class LLM::Anthropic
  ##
  # @private
  class StreamParser
    ##
    # Returns the fully constructed response body
    # @return [Hash]
    attr_reader :body

    ##
    # @param [LLM::Stream] stream
    # @return [LLM::Anthropic::StreamParser]
    def initialize(stream)
      @body = {"role" => "assistant", "content" => []}
      @stream = stream
    end

    ##
    # @param [Hash] chunk
    # @return [LLM::Anthropic::StreamParser]
    def parse!(chunk)
      tap { merge!(chunk) }
    end

    ##
    # Frees internal parser state used during streaming.
    # @return [void]
    def free
    end

    private

    def merge!(chunk)
      if chunk["type"] == "message_start"
        merge_message!(chunk["message"])
      elsif chunk["type"] == "content_block_start"
        @body["content"][chunk["index"]] = chunk["content_block"]
      elsif chunk["type"] == "content_block_delta"
        if chunk["delta"]["type"] == "text_delta"
          @body["content"][chunk["index"]]["text"] << chunk["delta"]["text"]
          emit_content(chunk["delta"]["text"])
        elsif chunk["delta"]["type"] == "input_json_delta"
          content = @body["content"][chunk["index"]]
          if Hash === content["input"]
            content["input"] = chunk["delta"]["partial_json"]
          else
            content["input"] ||= +""
            content["input"] << chunk["delta"]["partial_json"]
          end
        end
      elsif chunk["type"] == "message_delta"
        merge_message!(chunk["delta"]) if chunk["delta"]
        extras = chunk.reject { |k, _| k == "type" || k == "delta" }
        merge_message!(extras) unless extras.empty?
      elsif chunk["type"] == "content_block_stop"
        content = @body["content"][chunk["index"]]
        if content["input"]
          content["input"] = LLM.json.load(content["input"])
        end
        if content["type"] == "tool_use"
          emit_tool(content)
        end
      end
    end

    def merge_message!(message)
      message.each_pair do |key, value|
        if value.respond_to?(:each_pair)
          @body[key] ||= {}
          deep_merge!(@body[key], value)
        else
          @body[key] = value
        end
      end
    end

    def deep_merge!(target, source)
      source.each_pair do |key, value|
        if value.respond_to?(:each_pair) && target[key].respond_to?(:each_pair)
          deep_merge!(target[key], value)
        else
          target[key] = value
        end
      end
    end

    def emit_content(value)
      @stream.on_content(value)
    end

    def emit_tool(tool)
      function, error = resolve_tool(tool)
      error ? @stream.queue << error : @stream.on_tool_call(function)
    end

    def resolve_tool(tool)
      registered = @stream.__find__(tool["name"])
      fn = (registered || LLM::Function.new(tool["name"])).dup.tap do |fn|
        fn.id = tool["id"]
        fn.arguments = LLM::Anthropic.parse_tool_input(tool["input"])
        fn.tracer = @stream.extra[:tracer]
        fn.model = @stream.extra[:model]
        fn.intercept = @stream.extra[:intercept]
      end
      [fn, (registered ? nil : fn.unavailable)]
    end
  end
end
