# frozen_string_literal: true

class LLM::Google
  ##
  # @private
  class StreamParser
    ##
    # Returns the fully constructed response body
    # @return [Hash]
    attr_reader :body

    ##
    # @param [LLM::Stream] stream
    # @return [LLM::Google::StreamParser]
    def initialize(stream)
      @body = {"candidates" => []}
      @stream = stream
      @emits = {tools: []}
    end

    ##
    # @param [Hash] chunk
    # @return [LLM::Google::StreamParser]
    def parse!(chunk)
      tap { merge_chunk!(chunk) }
    end

    ##
    # Frees internal parser state used during streaming.
    # @return [void]
    def free
      @emits.clear
    end

    private

    def merge_chunk!(chunk)
      chunk.each do |key, value|
        k = key.to_s
        if k == "candidates"
          merge_candidates!(value)
        elsif k == "usageMetadata" &&
            Hash === @body["usageMetadata"] &&
            Hash === value
          @body["usageMetadata"] = @body["usageMetadata"].merge(value)
        else
          @body[k] = value
        end
      end
    end

    def merge_candidates!(deltas)
      deltas.each do |delta|
        index = delta["index"].to_i
        @body["candidates"][index] ||= {"content" => {"parts" => []}}
        candidate = @body["candidates"][index]
        delta.each do |key, value|
          k = key.to_s
          if k == "content"
            merge_candidate_content!(candidate["content"], value, index) if value
          else
            candidate[k] = value # Overwrite other fields
          end
        end
      end
    end

    def merge_candidate_content!(content, delta, cindex)
      delta.each do |key, value|
        k = key.to_s
        if k == "parts"
          content["parts"] ||= []
          merge_content_parts!(content["parts"], value, cindex) if value
        else
          content[k] = value
        end
      end
    end

    def merge_content_parts!(parts, deltas, cindex)
      deltas.each do |delta|
        if delta["text"]
          merge_text!(parts, delta)
        elsif delta["functionCall"]
          merge_function_call!(parts, delta, cindex)
        elsif delta["thoughtSignature"] and delta.size == 1
          merge_signature!(parts, delta)
        elsif delta["inlineData"]
          parts << delta
        elsif delta["functionResponse"]
          parts << delta
        elsif delta["fileData"]
          parts << delta
        else
          parts << delta
        end
      end
    end

    ##
    # @note
    #  Gemini can send a signature in a chunk of its own, after
    #  the part it belongs to. It is folded into that part so a
    #  streamed reply carries the same shape as a whole one, and
    #  a function call keeps the signature it needs on replay.
    #
    #  A delta that carries a signature beside other content is
    #  appended whole instead, which keeps the signature on the
    #  content it was sent with.
    def merge_signature!(parts, delta)
      last_existing_part = parts.last
      if Hash === last_existing_part
        last_existing_part["thoughtSignature"] = delta["thoughtSignature"]
      else
        parts << delta
      end
    end

    def merge_text!(parts, delta)
      last_existing_part = parts.last
      text = delta["text"]
      if Hash === last_existing_part && last_existing_part["text"]
        last_existing_part["text"] ||= +""
        last_existing_part["text"] << text
        merge_extra_keys!(last_existing_part, delta, "text")
        emit_content(text)
      else
        parts << delta
        emit_content(text)
      end
    end

    ##
    # Carries the keys a delta was sent with alongside the key
    # that decided where it goes, so nothing is dropped when a
    # delta is merged into the part before it.
    #
    # @param [Hash] target
    # @param [Hash] delta
    # @param [String] key
    #  The key the delta was merged by
    # @return [Hash]
    def merge_extra_keys!(target, delta, key)
      delta.each do |name, value|
        next if name == key
        target[name] = value
      end
    end

    def merge_function_call!(parts, delta, cindex)
      last_existing_part = parts.last
      last_call = Hash === last_existing_part ? last_existing_part["functionCall"] : nil
      delta_call = delta["functionCall"]
      if Hash === last_call && Hash === delta_call
        last_existing_part["functionCall"] = last_call.merge(delta_call)
        merge_extra_keys!(last_existing_part, delta, "functionCall")
      else
        parts << delta
      end
      emit_tool(parts.length - 1, cindex, parts.last || delta)
    end

    def emit_content(value)
      @stream.on_content(value)
    end

    def emit_tool(pindex, cindex, part)
      return unless complete_tool?(part)
      key = [cindex, pindex]
      return if @emits[:tools].include?(key)
      function, error = resolve_tool(part, cindex, pindex)
      @emits[:tools] << key
      error ? @stream.queue << error : @stream.on_tool_call(function)
    end

    def complete_tool?(part)
      call = part["functionCall"]
      call && call["name"] && Hash === call["args"]
    end

    def resolve_tool(part, cindex, pindex)
      call = part["functionCall"]
      registered = @stream.__find__(call["name"])
      fn = (registered || LLM::Function.new(call["name"])).dup.tap do |fn|
        fn.id = LLM::Google.tool_id(part:, cindex:, pindex:)
        fn.arguments = call["args"]
        fn.tracer = @stream.extra[:tracer]
        fn.model = @stream.extra[:model]
        fn.intercept = @stream.extra[:intercept]
      end
      [fn, (registered ? nil : fn.unavailable)]
    end
  end
end
