# frozen_string_literal: true

class LLM::OpenAI
  ##
  # @private
  class StreamParser
    EMPTY_HASH = {}.freeze

    ##
    # Returns the fully constructed response body
    # @return [Hash]
    attr_reader :body

    ##
    # @return [LLM::OpenAI::Chunk]
    def initialize(stream)
      @body = {}
      @stream = stream
      @emits = {tools: {}}
      @can_emit_content = stream.respond_to?(:on_content)
      @can_emit_reasoning_content = stream.respond_to?(:on_reasoning_content)
      @can_emit_tool_call = stream.respond_to?(:on_tool_call)
      @can_push_content = stream.respond_to?(:<<)
    end

    ##
    # @param [Hash] chunk
    # @return [LLM::OpenAI::Chunk]
    def parse!(chunk)
      tap { merge!(chunk) }
    end

    ##
    # Frees internal parser state used during streaming.
    # @return [void]
    def free
      @emits.clear
    end

    private

    def merge!(chunk)
      chunk.each do |key, value|
        if key == "choices"
          @body["choices"] ||= []
          merge_choices!(value)
        else
          @body[key] = value
        end
      end
    end

    def merge_choices!(choices)
      body_choices = @body["choices"]
      choices.each do |choice|
        index = choice["index"]
        delta = choice["delta"] || EMPTY_HASH
        target_message = if body_choice = body_choices[index]
          body_choice["message"]
        else
          body_choices[index] = {"message" => {"role" => "assistant"}}
          body_choices[index]["message"]
        end
        merge_delta!(target_message, delta)
      end
    end

    def merge_delta!(target_message, delta)
      if delta.key?("content") and (content = delta["content"])
        if target_content = target_message["content"]
          target_content << content
        else
          target_message["content"] = content
        end
        emit_content(content)
      end
      if delta.key?("reasoning_content") and (reasoning = delta["reasoning_content"])
        if target_reasoning = target_message["reasoning_content"]
          target_reasoning << reasoning
        else
          target_message["reasoning_content"] = reasoning
        end
        emit_reasoning_content(reasoning)
      end
      if delta.key?("tool_calls") and (tool_calls = delta["tool_calls"])
        merge_tools!(target_message, tool_calls)
      end
      delta.each do |key, value|
        next if value.nil? || key == "content" || key == "reasoning_content" || key == "tool_calls"
        target_message[key] = value
      end
    end

    def merge_single_delta!(target_message, delta)
      if content = delta["content"]
        if target_content = target_message["content"]
          target_content << content
        else
          target_message["content"] = content
        end
        emit_content(content)
        return
      end
      if reasoning = delta["reasoning_content"]
        if target_reasoning = target_message["reasoning_content"]
          target_reasoning << reasoning
        else
          target_message["reasoning_content"] = reasoning
        end
        emit_reasoning_content(reasoning)
        return
      end
      if tool_calls = delta["tool_calls"]
        merge_tools!(target_message, tool_calls)
      end
    end

    def merge_tools!(target, tools)
      target["tool_calls"] ||= []
      tools.each.with_index do |toola, index|
        tindex = toola["index"]
        tindex = index unless Integer === tindex && tindex >= 0
        toolb = target["tool_calls"][tindex]
        functiona = toola["function"]
        functionb = toolb && toolb["function"]
        if functiona && functionb
          # Append to existing function arguments
          merge_function!(functionb, functiona)
        else
          target["tool_calls"][tindex] = toola
        end
        emit_tool(target["tool_calls"][tindex], tindex)
      end
    end

    def merge_function!(target, source)
      if arguments = source["arguments"]
        if target_arguments = target["arguments"]
          target_arguments << arguments
        else
          target["arguments"] = arguments
        end
      end
      if name = source["name"]
        if target_name = target["name"]
          target_name << name
        else
          target["name"] = name
        end
      end
      return if source.length <= 2
      source.each do |func_key, func_value|
        next if func_key == "arguments" || func_key == "name"
        target[func_key] ||= +""
        target[func_key] << func_value
      end
    end

    def emit_content(value)
      if @can_emit_content
        @stream.on_content(value)
      elsif @can_push_content
        @stream << value
      end
    end

    def emit_reasoning_content(value)
      if @can_emit_reasoning_content
        @stream.on_reasoning_content(value)
      end
    end

    def emit_tool(tool, tindex)
      return unless @can_emit_tool_call
      return if @emits[:tools][tindex]
      function = tool["function"]
      return unless function && tool["id"] && function["name"]
      return unless arguments_complete?(function["arguments"])
      arguments = parse_arguments(function["arguments"])
      return unless arguments
      function, error = resolve_tool(tool, function, arguments)
      @emits[:tools][tindex] = true
      @stream.on_tool_call(function, error)
    end

    def resolve_tool(tool, function, arguments)
      registered = @stream.__find__(function["name"])
      fn = (registered || LLM::Function.new(function["name"])).dup.tap do |fn|
        fn.id = tool["id"]
        fn.arguments = arguments
        fn.tracer = @stream.extra[:tracer]
        fn.model = @stream.extra[:model]
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

    def arguments_complete?(arguments)
      value = arguments.to_s.rstrip
      !value.empty? && value.end_with?("}")
    end
  end
end
