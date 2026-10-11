# frozen_string_literal: true

module LLM
  ##
  # The {LLM::Tracer::PrettyLogger LLM::Tracer::PrettyLogger} class
  # writes human-readable request and tool call logs to a console
  # or file. Each event is a single line with the relevant context
  # inline, no structured JSON.
  #
  # @example
  #   llm = LLM.openai(key: ENV["KEY"])
  #   llm.tracer = LLM::Tracer.pretty_logger(llm)
  #
  # @example Writing to a file
  #   llm.tracer = LLM::Tracer.pretty_logger(llm, path: "log.txt")
  class Tracer::PrettyLogger < Tracer
    ##
    # @param (see LLM::Tracer#initialize)
    def initialize(provider, options = {})
      super
      setup!(**options)
    end

    ##
    # @param (see LLM::Tracer#on_request_start)
    # @return [void]
    def on_request_start(operation:, model: nil, **)
      @start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      name = operation == "chat" ? "chat" : operation
      @io.puts "#{timestamp} #{provider_name} #{name} (#{model || "default"})"
    end

    ##
    # @param (see LLM::Tracer#on_request_finish)
    # @return [void]
    def on_request_finish(operation:, res:, model: nil, **)
      elapsed = @start ? (Process.clock_gettime(Process::CLOCK_MONOTONIC) - @start).round(2) : nil
      tokens = format_tokens(res)
      name = operation == "chat" ? "chat" : operation
      parts = ["#{timestamp} #{provider_name} #{name} done"]
      parts << tokens if tokens
      parts << "#{elapsed}s" if elapsed
      @io.puts parts.join(", ")
    end

    ##
    # @param (see LLM::Tracer#on_request_error)
    # @return [void]
    def on_request_error(ex:, **)
      @io.puts "#{timestamp} #{provider_name} error #{ex.class}: #{ex.message}"
    end

    ##
    # @note An "ending" describes the method
    #  that matches the end of a tool call, and it can be one of:
    #  on_tool_finish, on_tool_error or on_tool_interrupt.
    # @param (see LLM::Tracer#on_tool_start)
    # @return [LLM::Object]
    #  The span an ending is handed, with the call's id and name
    def on_tool_start(id:, name:, arguments:, **)
      @io.puts "#{timestamp} #{name}(#{format_arguments(arguments)})"
      LLM::Object.from(id:, name:)
    end

    ##
    # @param (see LLM::Tracer#on_tool_finish)
    # @return [void]
    def on_tool_finish(result:, **)
      @io.puts "#{timestamp} #{result.name} -> #{format_value(result.value)}"
    end

    ##
    # @param (see LLM::Tracer#on_tool_error)
    # @return [void]
    def on_tool_error(ex:, **)
      @io.puts "#{timestamp} tool error #{ex.class}: #{ex.message}"
    end

    ##
    # @note A tool call that has been interrupted is closed
    #  by this callback. It receives a span that it can match
    #  back to `on_tool_start`. In the case of this tracer
    #  we just log values, though.
    # @param (see LLM::Tracer#on_tool_interrupt)
    # @return [void]
    def on_tool_interrupt(ex:, span:, **)
      @io.puts "#{timestamp} tool #{span.name} (#{format_id(span.id)}) received an interrupt"
    end

    ##
    # @param (see LLM::Tracer#on_interrupt)
    # @return [void]
    def on_interrupt(scope:, **)
      @io.puts "#{timestamp} #{provider_name} interrupt received (scope=#{scope})"
    end

    ##
    # No-op.
    # @return [nil]
    def on_exit
      nil
    end

    private

    def setup!(io: $stderr, path: nil)
      @io = path ? ::File.open(path, "a") : io
      @start = nil
    end

    def timestamp
      Time.now.strftime("%H:%M:%S")
    end

    def format_tokens(res)
      usage = res.usage
      if usage.input_tokens and usage.output_tokens
        "in=#{usage.input_tokens} out=#{usage.output_tokens}"
      elsif usage.input_tokens
        "in=#{usage.input_tokens}"
      elsif usage.output_tokens
        "out=#{usage.output_tokens}"
      end
    end

    def format_arguments(args, max: 50)
      return "" unless args
      case args
      when Hash, LLM::Object
        result = args.map { |k, v| "#{k}: #{format_value(v)}" }.join(", ")
      when Array
        result = args.map { |v| format_value(v) }.join(", ")
      else
        result = args.inspect
      end
      result.size > max ? "#{result[0...max - 1]}..." : result
    end

    def format_value(value, max: 18)
      case value
      when String
        value.size > max ? "#{value[0...max]}...".inspect : value.inspect
      when Array
        items = value.take(2).map { format_value(_1, max: 10) }
        items << "..." if value.size > 2
        "[#{items.join(", ")}]"
      when Hash
        "{...}"
      when nil
        "nil"
      else
        str = value.inspect
        str.size > max ? "#{str[0...max]}..." : str
      end
    end

    ##
    # A call id, which is a long string that reads as gibberish:
    # ten characters are enough to tell two of them apart.
    def format_id(id)
      id = id.to_s
      id.size > 10 ? "#{id[0, 10]}..." : id
    end
  end
end
