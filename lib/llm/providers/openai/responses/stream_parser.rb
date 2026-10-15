# frozen_string_literal: true

class LLM::OpenAI
  ##
  # @private
  class Responses::StreamParser
    EMPTY_HASH = {}.freeze

    ##
    # Returns the fully constructed response body
    # @return [Hash]
    attr_reader :body

    ##
    # @param [LLM::Stream] stream
    # @return [LLM::OpenAI::Responses::StreamParser]
    def initialize(stream)
      @body = {"output" => []}
      @stream = stream
      @emits = {tools: {}}
      @cached_output_index = nil
      @cached_output_item = nil
      @cached_content_index = nil
      @cached_content_part = nil
    end

    ##
    # @param [Hash] chunk
    # @return [LLM::OpenAI::Responses::StreamParser]
    def parse!(chunk)
      tap { handle_event(chunk) }
    end

    ##
    # Frees internal parser state used during streaming.
    # @return [void]
    def free
      @emits.clear
      clear_cache!
    end

    private

    ##
    # @group Dispatchers

    def handle_event(chunk)
      output = @body["output"]
      type = chunk["type"]
      if type == "response.output_text.delta"
        merge_output_text_delta!(output, chunk)
      elsif type == "response.content_part.added"
        merge_content_part!(output, chunk)
      elsif type == "response.output_item.added"
        merge_output_item!(output, chunk)
      elsif type == "response.function_call_arguments.delta"
        merge_function_call_arguments_delta!(output, chunk)
      elsif type == "response.function_call_arguments.done"
        merge_function_call_arguments_done!(output, chunk)
      elsif type == "response.output_item.done"
        merge_output_item!(output, chunk)
      elsif type == "response.content_part.done"
        merge_content_part!(output, chunk, part_key: "part")
      else
        case type
        when "response.created"
          merge_response_created!(chunk)
        when "response.in_progress", "response.completed"
          merge_response_state!(output, chunk)
        when "response.reasoning_summary_text.delta"
          merge_reasoning_summary_text_delta!(output, chunk)
        when "response.reasoning_summary_text.done"
          merge_reasoning_summary_text_done!(output, chunk)
        end
      end
    end

    ##
    # @endgroup

    ##
    # @group Mergers

    def merge_response_created!(chunk)
      clear_cache!
      chunk.each do |k, v|
        next if k == "type"
        @body[k] = v
      end
      @body["output"] ||= []
    end

    def merge_response_state!(output, chunk)
      clear_cache!
      response = chunk["response"] || EMPTY_HASH
      response.each do |k, v|
        next if k == "output" && Array === output && output.any?
        @body[k] = v
      end
      @body["output"] ||= response["output"] || []
    end

    def merge_output_item!(output, chunk)
      output_index = chunk["output_index"]
      item = chunk["item"]
      output[output_index] = item
      item["content"] ||= [] if item["type"] == "message" || item.key?("content")
      item["summary"] ||= [] if item["type"] == "reasoning"
      cache_output_item!(output_index, item)
    end

    def merge_content_part!(output, chunk, part_key: "part")
      output_index = chunk["output_index"]
      content_index = chunk["content_index"]
      part = chunk[part_key]
      output_item = output_item_at(output, output_index)
      unless output_item
        output_item = {"content" => []}
        output[output_index] = output_item
        cache_output_item!(output_index, output_item)
      end
      content = output_item["content"] ||= []
      content[content_index] = part
      cache_content_part!(content_index, part)
    end

    def merge_output_text_delta!(output, chunk)
      content_part = content_part_at(output, chunk["output_index"], chunk["content_index"])
      if content_part && content_part["type"] == "output_text"
        delta_text = chunk["delta"]
        if text = content_part["text"]
          text << delta_text
        else
          content_part["text"] = delta_text
        end
        emit_content(delta_text)
      end
    end

    def merge_reasoning_summary_text_delta!(output, chunk)
      output_item = output_item_at(output, chunk["output_index"])
      if output_item && output_item["type"] == "reasoning"
        summary_index = chunk["summary_index"] || 0
        delta = chunk["delta"]
        summary = output_item["summary"] ||= []
        if summary_item = summary[summary_index]
          summary_item["text"] << delta
        else
          summary[summary_index] = {"type" => "summary_text", "text" => delta}
        end
        emit_reasoning_content(delta)
      end
    end

    def merge_reasoning_summary_text_done!(output, chunk)
      output_item = output_item_at(output, chunk["output_index"])
      if output_item && output_item["type"] == "reasoning"
        summary_index = chunk["summary_index"] || 0
        output_item["summary"] ||= []
        output_item["summary"][summary_index] = {
          "type" => "summary_text",
          "text" => chunk["text"]
        }
      end
    end

    def merge_function_call_arguments_delta!(output, chunk)
      output_item = output_item_at(output, chunk["output_index"])
      if output_item && output_item["type"] == "function_call"
        if arguments = output_item["arguments"]
          arguments << chunk["delta"]
        else
          output_item["arguments"] = chunk["delta"]
        end
      end
    end

    def merge_function_call_arguments_done!(output, chunk)
      output_item = output_item_at(output, chunk["output_index"])
      if output_item && output_item["type"] == "function_call"
        output_item["arguments"] = chunk["arguments"]
        emit_tool(chunk["output_index"], output_item)
      end
    end

    ##
    # @endgroup

    ##
    # @group Cache

    def output_item_at(output, output_index)
      if @cached_output_index == output_index
        @cached_output_item
      else
        cache_output_item!(output_index, output[output_index])
      end
    end

    def content_part_at(output, output_index, content_index)
      if @cached_output_index == output_index && @cached_content_index == content_index
        @cached_content_part
      else
        output_item = output_item_at(output, output_index)
        content = output_item && output_item["content"]
        cache_content_part!(content_index, content && content[content_index])
      end
    end

    def cache_output_item!(output_index, output_item)
      @cached_output_index = output_index
      @cached_output_item = output_item
      @cached_content_index = nil
      @cached_content_part = nil
      output_item
    end

    def cache_content_part!(content_index, content_part)
      @cached_content_index = content_index
      @cached_content_part = content_part
      content_part
    end

    def clear_cache!
      @cached_output_index = nil
      @cached_output_item = nil
      @cached_content_index = nil
      @cached_content_part = nil
    end

    ##
    # @endgroup

    ##
    # @group Emitters

    def emit_content(value)
      @stream.on_content(value)
    end

    def emit_reasoning_content(value)
      @stream.on_reasoning_content(value)
    end

    def emit_tool(index, tool)
      return if @emits[:tools][index]
      return unless tool["call_id"] && tool["name"]
      arguments = parse_arguments(tool["arguments"])
      return unless arguments
      function, error = resolve_tool(tool, arguments)
      @emits[:tools][index] = true
      error ? @stream.queue << error : @stream.on_tool_call(function)
    end

    ##
    # @endgroup

    ##
    # @group Resolvers

    def resolve_tool(tool, arguments)
      registered = @stream.__find__(tool["name"])
      fn = (registered || LLM::Function.new(tool["name"])).dup.tap do |fn|
        fn.id = tool["call_id"]
        fn.arguments = arguments
        fn.tracer = @stream.extra[:tracer]
        fn.model = @stream.extra[:model]
        fn.intercept = @stream.extra[:intercept]
      end
      [fn, (registered ? nil : fn.unavailable)]
    end

    def parse_arguments(arguments)
      return nil if arguments.to_s.empty?
      parsed = LLM.json.load(arguments)
      Hash === parsed ? parsed : nil
    rescue *LLM.json.parser_error
      nil
    end

    ##
    # @endgroup
  end
end
