# frozen_string_literal: true

module LLM
  ##
  # The {LLM::Tracer::EnhancedLogger LLM::Tracer::EnhancedLogger} class
  # writes a readable log of every chat request, tool call and
  # interrupt, then a summary when the tracer exits. Color is used
  # when the IO the tracer writes to is a terminal.
  #
  # @example
  #   llm = LLM.openai(key: ENV["KEY"])
  #   llm.tracer = LLM::Tracer.enhanced_logger(llm)
  #
  # @example Writing to a file
  #   llm.tracer = LLM::Tracer.enhanced_logger(llm, path: "log.txt")
  class Tracer::EnhancedLogger < Tracer
    ##
    # @return [Integer]
    #  The width of a rule
    RULE = 58

    ##
    # @param (see LLM::Tracer#initialize)
    def initialize(llm, options = {})
      super
      setup!(**options)
    end

    ##
    # @param (see LLM::Tracer#on_request_start)
    # @return [void]
    def on_request_start(operation:, model: nil, request_id:, **)
      @model = model || @model
      @started[request_id] = clock
      return unless operation == "chat"
      @counts.requests += 1
      header
      say "#{paint("->", :cyan)} #{llm.name}#{model ? " #{model}" : ""}"
    end

    ##
    # @param (see LLM::Tracer#on_request_finish)
    # @return [void]
    def on_request_finish(operation:, res:, request_id:, **)
      elapsed = elapsed!(request_id)
      return unless operation == "chat"
      tokens = format_tokens(res)
      parts = [paint("<-", :green)]
      parts << format("%.2fs", elapsed) if elapsed
      parts << tokens if tokens
      say parts.join("  ")
    end

    ##
    # @param (see LLM::Tracer#on_request_error)
    # @return [void]
    def on_request_error(ex:, **)
      @counts.errors += 1
      say "#{paint("!!", :red)} #{ex.class}: #{ex.message}"
    end

    ##
    # @param (see LLM::Tracer#on_tool_start)
    # @return [LLM::Object]
    #  The span an ending is handed, with the call's id and name
    def on_tool_start(id:, name:, arguments:, **)
      @spans[id] = clock
      @counts.tools[name] = @counts.tools.fetch(name, 0) + 1
      say "   #{paint("..", :yellow)} #{name}(#{format_arguments(arguments)})"
      LLM::Object.from(id:, name:)
    end

    ##
    # @param (see LLM::Tracer#on_tool_finish)
    # @return [void]
    def on_tool_finish(result:, **)
      duration = span!(result.id)
      if duration && (@counts.slowest.nil? || duration > @counts.slowest.last)
        @counts.slowest = [result.name, duration]
      end
      timing = duration ? "  #{format("%.2fs", duration)}" : ""
      say "   #{paint("ok", :green)} #{result.name}#{timing}"
    end

    ##
    # @param (see LLM::Tracer#on_tool_error)
    # @return [void]
    def on_tool_error(ex:, **)
      @counts.failed += 1
      say "   #{paint("no", :red)} #{ex.value[:type]}: #{ex.value[:message]}"
    end

    ##
    # @param (see LLM::Tracer#on_tool_interrupt)
    # @return [void]
    def on_tool_interrupt(ex:, span:, **)
      @counts.failed += 1
      say "   #{paint("no", :red)} tool #{span.name} (#{format_id(span.id)}) received an interrupt"
    end

    ##
    # @param (see LLM::Tracer#on_interrupt)
    # @return [void]
    def on_interrupt(scope:, **)
      say "#{paint("!!", :red)} #{llm.name} interrupt received (scope=#{scope})"
    end

    ##
    # Writes the summary, then closes the file the tracer opened.
    # @return [nil]
    def on_exit
      summary
      @file&.close
      @file = nil
      nil
    end

    private

    def setup!(io: $stderr, path: nil)
      @file = path ? ::File.open(path, "a") : nil
      @io = LLM::Paint::IO.new(io: @file || io)
      @opened = clock
      @started = {}
      @spans = {}
      @header = false
      @counts = LLM::Object.from(
        requests: 0, input: 0, output: 0,
        tools: {}, failed: 0, errors: 0, slowest: nil
      )
    end

    ##
    # Opens the log with a rule, once.
    # @return [void]
    def header
      return if @header
      @header = true
      rule
    end

    ##
    # @return [void]
    def summary
      return if @counts.requests.zero? && @counts.tools.empty?
      say
      rule
      stat "provider", llm.name
      stat "model", @model if @model
      stat "requests", @counts.requests
      stat "tools", tools_note
      stat "tokens", tokens_note
      if (price = cost)
        stat "cost", price
      end
      if @counts.slowest
        stat "slowest", "#{@counts.slowest.first} #{format("%.2fs", @counts.slowest.last)}"
      end
      stat "errors", @counts.errors unless @counts.errors.zero?
      stat "time", format("%.2fs", clock - @opened)
      rule
      say
    end

    ##
    # @return [String]
    def tools_note
      total = @counts.tools.values.sum
      return "0" if total.zero?
      count = @counts.failed.zero? ? total.to_s : "#{total} (#{@counts.failed} failed)"
      breakdown = @counts.tools.map { |name, calls| "#{name} #{calls}" }.join(", ")
      [count, trim(breakdown, limit: 32)].join("  ")
    end

    ##
    # @return [String]
    def tokens_note
      "#{abbreviate(@counts.input)} in / #{abbreviate(@counts.output)} out"
    end

    ##
    # Adds the usage of a response to the running total, and returns
    # the usage of that response as text.
    # @param [LLM::Response] res
    # @return [String, nil]
    def format_tokens(res)
      usage = res.usage
      return unless usage
      input = usage.input_tokens.to_i
      output = usage.output_tokens.to_i
      @counts.input += input
      @counts.output += output
      "#{abbreviate(input)} in / #{abbreviate(output)} out"
    end

    ##
    # The registry does not price every model, in which case there
    # is nothing to report.
    # @return [String, nil]
    def cost
      return unless @model
      price = llm.registry.cost(model: @model)
      total = (price.input.to_f * @counts.input + price.output.to_f * @counts.output) / 1_000_000.0
      format("~$%.4f", total)
    rescue StandardError
      nil
    end

    ##
    # @param [Integer] count
    # @return [String]
    def abbreviate(count)
      count < 1000 ? count.to_s : format("%.1fk", count / 1000.0)
    end

    ##
    # @param [String] name
    # @param [Object] value
    # @return [void]
    def stat(name, value)
      say "   #{label(name)} #{value}"
    end

    ##
    # @param [String] text
    # @return [String]
    def label(text)
      paint(format("%-10s", text), :faint)
    end

    ##
    # @return [void]
    def rule
      say paint("-" * RULE, :faint)
    end

    ##
    # @param [String] line
    # @return [Integer]
    def say(line = "")
      @io.puts(line)
    end

    ##
    # @param [String] text
    # @param [Array<Symbol>] colours
    # @return [String]
    def paint(text, *colours)
      return text.to_s unless @io.color?
      LLM::Paint[text, *colours]
    end

    ##
    # @return [Float]
    def clock
      Process.clock_gettime(Process::CLOCK_MONOTONIC)
    end

    ##
    # @param [String, nil] id
    # @return [Float, nil]
    def elapsed!(id)
      started = @started.delete(id)
      clock - started unless started.nil?
    end

    ##
    # @param [String, nil] id
    # @return [Float, nil]
    def span!(id)
      started = @spans.delete(id)
      clock - started unless started.nil?
    end

    ##
    # @param [Object] text
    # @param [Integer] limit
    # @return [String]
    def trim(text, limit: 40)
      text = text.to_s
      text.size > limit ? "#{text[0, limit]}..." : text
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
