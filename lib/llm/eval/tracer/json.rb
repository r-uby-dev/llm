# frozen_string_literal: true

module LLM::Eval::Tracer
  ##
  # JSON-based tracer.
  class JSON < LLM::Tracer::Null
    ##
    # @return [LLM::Eval]
    attr_reader :eval

    ##
    # @param (see LLM::Tracer#initialize)
    # @return (see LLM::Tracer#initialize)
    def initialize(llm, options = {})
      super
      @eval = options[:eval]
      @provider = llm.name
      @started_at = Time.now.utc
      @started = nil
      @spans = {}
      @requests = []
      @tools = []
      @errors = []
      @root = File.join(
        Dir.getwd,
        "runs",
        @eval.name,
        llm.name.to_s,
        eval.model.to_s,
        eval.sample.to_s
      )
    end

    ##
    # @param (see LLM::Tracer#on_request_start)
    # @return [void]
    def on_request_start(operation:, model: nil, **)
      @started = clock
      @model ||= model
      return unless operation == "chat"
      @requests << {"index" => @requests.size + 1, "model" => model}
    end

    ##
    # @param (see LLM::Tracer#on_request_finish)
    # @return [void]
    def on_request_finish(operation:, res: nil, **)
      return unless operation == "chat"
      request = @requests.last
      return if request.nil?
      input, output = tokens(res)
      request["duration_s"] = elapsed
      request["ok"] = res.respond_to?(:ok?) ? res.ok? : true
      request["input_tokens"] = input
      request["output_tokens"] = output
      request["reply"] = reply(res)
      request["reasoning"] = reasoning(res)
    end

    ##
    # @param (see LLM::Tracer#on_request_error)
    # @return [void]
    def on_request_error(ex:, **)
      @errors << {"kind" => "request", "class" => ex.class.to_s, "message" => ex.message}
      request = @requests.last
      request["error"] = ex.message if request
    end

    ##
    # @param (see LLM::Tracer#on_tool_start)
    # @return [LLM::Object]
    #  The span an ending is handed, with the call's id and name
    def on_tool_start(id:, name:, arguments:, **)
      @spans[id] = clock
      @tools << {"name" => name, "arguments" => plain(arguments)}
      LLM::Object.from(id:, name:)
    end

    ##
    # @param (see LLM::Tracer#on_tool_finish)
    # @return [void]
    def on_tool_finish(result:, **)
      tool = @tools.last
      return if tool.nil?
      tool["duration_s"] = span(result.id)
      tool["ok"] = true
    end

    ##
    # @param (see LLM::Tracer#on_tool_error)
    # @return [void]
    def on_tool_error(ex:, **)
      message = ex.value[:message].to_s
      @errors << {"kind" => "tool", "class" => ex.value[:type].to_s, "message" => message}
      tool = @tools.last
      tool["error"] = message if tool
    end

    ##
    # @param (see LLM::Tracer#on_tool_interrupt)
    # @return [void]
    def on_tool_interrupt(ex:, span:, **)
      @errors << {"kind" => "tool", "class" => ex.class.to_s, "message" => ex.message}
      tool = @tools.last
      tool["error"] = ex.message if tool
    end

    ##
    # @param (see LLM::Tracer#on_interrupt)
    # @return [void]
    def on_interrupt(scope:, **)
      @errors << {"kind" => scope.to_s, "class" => "LLM::Interrupt", "message" => "interrupted"}
    end

    ##
    # Writes the run to disk.
    # @return [String]
    #  Returns the path that was written
    def on_exit
      FileUtils.mkdir_p(@root)
      dest = File.join(@root, "sample.json")
      File.write(dest, LLM.json.dump(report))
      dest
    end

    private

    def report
      {
        "eval" => @eval.name,
        "provider" => @provider,
        "model" => @model,
        "score" => @eval.result,
        "started_at" => @started_at.iso8601,
        "duration_s" => (Time.now.utc - @started_at).round(2),
        "totals" => totals,
        "penalties" => @eval.penalties,
        "steps" => @eval.steps,
        "requests" => @requests,
        "tool_calls" => @tools,
        "errors" => @errors,
        "runtime" => runtime
      }
    end

    ##
    # @return [Hash]
    def runtime
      @eval.agent.to_h
    rescue StandardError
      {}
    end

    def totals
      {
        "requests" => @requests.size,
        "tool_calls" => @tools.size,
        "errors" => @errors.size,
        "input_tokens" => @requests.sum { it["input_tokens"] || 0 },
        "output_tokens" => @requests.sum { it["output_tokens"] || 0 }
      }
    end

    def clock
      Process.clock_gettime(Process::CLOCK_MONOTONIC)
    end

    def elapsed
      return 0.0 if @started.nil?
      (clock - @started).round(2)
    end

    def span(id)
      started = @spans.delete(id)
      return nil if started.nil?
      (clock - started).round(2)
    end

    def tokens(res)
      return [0, 0] if res.nil?
      usage = res.respond_to?(:usage) ? res.usage : nil
      return [0, 0] if usage.nil?
      usage = LLM::Usage.from(usage)
      [usage.input_tokens, usage.output_tokens]
    rescue StandardError
      [0, 0]
    end

    def reply(res)
      clip(res, :content)
    end

    def reasoning(res)
      clip(res, :reasoning_content)
    end

    def clip(res, name)
      return "" if res.nil? || !res.respond_to?(name)
      text = res.public_send(name).to_s
      text.size > 2000 ? "#{text[0, 2000]}..." : text
    rescue StandardError
      ""
    end

    def plain(value)
      LLM.json.parse(LLM.json.generate(value))
    rescue StandardError
      value.to_s
    end

    def slug(text)
      text.to_s.downcase.gsub(/[^a-z0-9]+/, "-").gsub(/\A-+|-+\z/, "")
    end
  end
end
