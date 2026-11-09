# frozen_string_literal: true

module LLM::Eval::Tracer
  ##
  # Console-based tracer.
  class Console < LLM::Tracer::Null
    ##
    # @return [Integer]
    RULE = 58

    ##
    # @param (see LLM::Tracer#initialize)
    # @return (see LLM::Tracer#initialize)
    def initialize(llm, options = {})
      super
      @tracer = LLM::Object.from(
        io: options[:io] || $stdout, eval: options[:eval],
        provider: llm.name, model: nil, spans: {},
        started: nil, opened: clock, header: false
      )
      @counts = LLM::Object.from(
        turns: 0, requests: 0, input: 0, output: 0,
        tools: {}, failed: 0, errors: 0, slowest: nil
      )
    end

    ##
    # @return [LLM::Eval]
    def eval
      @tracer.eval
    end

    ##
    # @return [String]
    def rundir
      File.join(Dir.getwd, "runs", eval.name,
                llm.name.to_s, eval.model.to_s,
                eval.sample.to_s)
    end

    ##
    # @param (see LLM::Tracer#start_trace)
    # @return [void]
    def start_trace(...)
      @counts.turns += 1
      super
    end

    ##
    # @param (see LLM::Tracer#on_request_start)
    # @return [void]
    def on_request_start(operation:, model: nil, **)
      @tracer.started = clock
      @tracer.model ||= model
      @counts.requests += 1 if operation == "chat"
      return unless operation == "chat"
      header
      say "#{paint("->", :cyan)} #{@tracer.provider}#{model ? " #{model}" : ""}"
    end

    ##
    # @param (see LLM::Tracer#on_request_finish)
    # @return [void]
    def on_request_finish(operation:, res:, **)
      return unless operation == "chat"
      usage = res.usage
      @counts.input += usage.input_tokens
      @counts.output += usage.output_tokens
      say "#{paint("<-", :green)} #{format("%.1fs", clock - @tracer.started)}"
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
      @tracer.spans[id] = clock
      @counts.tools[name] = @counts.tools.fetch(name, 0) + 1
      say "   #{paint("..", :yellow)} #{name} #{trim(arguments)}"
      LLM::Object.from(id:, name:)
    end

    ##
    # @param (see LLM::Tracer#on_tool_finish)
    # @return [void]
    def on_tool_finish(result:, **)
      duration = took(result.id)
      if duration && (@counts.slowest.nil? || duration > @counts.slowest.last)
        @counts.slowest = [result.name, duration]
      end
      say "   #{paint("ok", :green)} #{result.name} #{duration ? format("%.2fs", duration) : "?"}"
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
      say "   #{paint("no", :red)} #{span.name} interrupted: #{ex.message}"
    end

    ##
    # @param (see LLM::Tracer#on_interrupt)
    # @return [void]
    def on_interrupt(scope:, **)
      say "#{paint("!!", :red)} #{scope} interrupted"
    end

    ##
    # @return [void]
    def on_exit
      return unless eval.result
      buffer = StringIO.new
      io = @tracer.io
      @tracer.io = buffer
      summary
      @tracer.io = io
      io.print(buffer.string)
      FileUtils.mkdir_p(rundir)
      File.write(File.join(rundir, "sample.txt"), buffer.string.gsub(/\e\[[0-9;]*m/, ""))
    end

    private

    def summary
      say
      rule
      say "   #{paint(@name, :bold)}" unless @name.nil?
      brief = [@tracer.provider, @tracer.model].compact.join(" ")
      say "   #{paint(brief, :cyan)}"
      say
      stat "turns", @counts.turns
      stat "requests", @counts.requests
      stat "tools", tools_note
      stat "tokens", tokens_note
      stat "cost", cost
      slowest = @counts.slowest
      stat "slowest", "#{slowest.first} #{format("%.2fs", slowest.last)}" unless slowest.nil?
      stat "errors", @counts.errors unless @counts.errors.zero?
      stat "time", format("%.1fs", clock - @tracer.opened)
      say
      score_line
      eval.penalties.each do |penalty|
        say "   #{paint("!", :red)} #{penalty[:why]} #{format("-%.2f", penalty[:by])}"
      end
      reports
      rule
      say
    end

    ##
    # @return [void]
    def score_line
      score = eval.result
      say "   #{label("score")} #{paint(format("%.2f", score), :bold)} " \
          "#{gauge(score)} #{paint(format("%.0f%%", score * 100), :faint)}"
    end

    ##
    # @return [void]
    def reports
      dir = rundir.sub("#{Dir.getwd}/", "")
      say
      say "   #{paint("Reports", :bold)}"
      say "   run  #{File.join(File.dirname(dir), "run.txt")}"
      say "   text #{File.join(dir, "sample.txt")}"
      say "   json #{File.join(dir, "sample.json")}"
    end

    ##
    # @param [Float] score
    # @return [String]
    def gauge(score)
      width = 24
      filled = (score.clamp(0.0, 1.0) * width).round
      colour = if score >= 0.999 then :green
               elsif score <= 0.0 then :red
               else :yellow
               end
      paint(" " * filled, colour, :inverse) + paint("-" * (width - filled), :faint)
    end

    def stat(name, value)
      say "   #{label(name)} #{value}"
    end

    def label(text)
      paint(format("%-10s", text), :faint)
    end

    def rule
      say paint("-" * RULE, :faint)
    end

    ##
    # @return [String]
    def tools_note
      total = @counts.tools.values.sum
      count = @counts.failed.zero? ? total.to_s : "#{total} (#{@counts.failed} failed)"
      breakdown = @counts.tools.map { |name, calls| "#{name} #{calls}" }.join(", ")
      [count, trim(breakdown, limit: 32)].reject(&:empty?).join(" - ")
    end

    ##
    # @return [String]
    def tokens_note
      "#{abbreviate(@counts.input)} in / #{abbreviate(@counts.output)} out"
    end

    ##
    # @return [String]
    def cost
      price = llm.registry.cost(model: eval.model)
      total = ((price.input.to_f * @counts.input) + (price.output.to_f * @counts.output)) / 1_000_000.0
      format("~$%.4f", total)
    end

    ##
    # @param [Integer] count
    # @return [String]
    def abbreviate(count)
      count < 1000 ? count.to_s : format("%.1fk", count / 1000.0)
    end

    def header
      return if @tracer.header
      @tracer.header = true
      say paint(@name, :bold) unless @name.nil?
    end

    def say(line = "")
      @tracer.io.puts(line)
    end

    def clock
      Process.clock_gettime(Process::CLOCK_MONOTONIC)
    end

    ##
    # @param [String] id
    # @return [Float, nil]
    def took(id)
      started = @tracer.spans.delete(id)
      clock - started unless started.nil?
    end

    ##
    # @param [Object] arguments
    # @param [Integer] limit
    # @return [String]
    def trim(arguments, limit: 78)
      text = arguments.to_s
      text.size > limit ? "#{text[0, limit]}..." : text
    end

    ##
    # @param [String] text
    # @param [Array<Symbol>] colours
    # @return [String]
    def paint(text, *colours)
      LLM::Paint[text, *colours]
    end
  end
end
