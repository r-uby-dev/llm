# frozen_string_literal: true

class LLM::Tracer
  ##
  # A tracer that fans out every tracing callback to a set of
  # tracers, so a request can (for example) be logged to a file
  # and exported to OpenTelemetry at the same time.
  #
  # {on_request_start} and {on_tool_start} return an array with
  # one span per tracer, in the same order as {#tracers}. Pass the
  # array back as `span:` to the matching finish, error, or
  # interrupt callback, and each tracer is handed back the span
  # it returned.
  #
  # A tracer that raises does not take the others down with it:
  # the error is reported the same way
  # {LLM::Tracer::Rescue LLM::Tracer::Rescue} reports a crashed
  # tracer, and the remaining tracers still run.
  #
  # @example
  #   LLM::Tracer::Multi.new(
  #     LLM::Tracer.logger(llm, io: $stdout),
  #     LLM::Tracer.telemetry(llm)
  #   )
  class Multi < self
    ##
    # Returns the tracer(s) under the supervision of Multi
    # @return [Array<LLM::Tracer>]
    attr_reader :tracers

    ##
    # @param [Array<LLM::Tracer>] tracers
    #  The tracers to fan out to. A Multi has no provider
    #  of its own.
    def initialize(*tracers)
      super(nil)
      @tracers = tracers
    end

    ##
    # @param (see LLM::Tracer#on_request_start)
    # @return [Array]
    #  One span per tracer, in the same order as {#tracers}
    def on_request_start(operation:, request_id:, model: nil, inputs: nil)
      @tracers.map { _1.on_request_start(operation:, request_id:, model:, inputs:) }
    end

    ##
    # @param (see LLM::Tracer#on_request_finish)
    # @return [void]
    def on_request_finish(operation:, res:, model: nil, span: nil, outputs: nil, metadata: nil, request_id:)
      span.each.with_index do |s, i|
        @tracers[i].on_request_finish(operation:, res:, model:, span: s, outputs:, metadata:, request_id:)
      end
    end

    ##
    # @param (see LLM::Tracer#on_request_error)
    # @return [void]
    def on_request_error(ex:, span:, request_id:)
      span.each.with_index do |s, i|
        @tracers[i].on_request_error(ex:, span: s, request_id:)
      end
    end

    ##
    # @param (see LLM::Tracer#on_tool_start)
    # @return [Array]
    #  One span per tracer, in the same order as {#tracers}
    def on_tool_start(id:, name:, arguments:, model:)
      @tracers.map { _1.on_tool_start(id:, name:, arguments:, model:) }
    end

    ##
    # @param (see LLM::Tracer#on_tool_interrupt)
    # @return [void]
    def on_tool_interrupt(ex:, span:, started_at:, finished_at:)
      span.each.with_index do |s, i|
        @tracers[i].on_tool_interrupt(ex:, span: s, started_at:, finished_at:)
      end
    end

    ##
    # @param (see LLM::Tracer#on_tool_finish)
    # @return [void]
    def on_tool_finish(result:, span:, started_at:, finished_at:)
      span.each.with_index do |s, i|
        @tracers[i].on_tool_finish(result:, span: s, started_at:, finished_at:)
      end
    end

    ##
    # @param (see LLM::Tracer#on_tool_error)
    # @return [void]
    def on_tool_error(ex:, span:, started_at:, finished_at:)
      span.each.with_index do |s, i|
        @tracers[i].on_tool_error(ex:, span: s, started_at:, finished_at:)
      end
    end

    ##
    # @param (see LLM::Tracer#on_interrupt)
    # @return [void]
    def on_interrupt(scope:, span: nil, request_id: nil)
      spans = span || Array.new(@tracers.size)
      spans.each.with_index do |s, i|
        @tracers[i].on_interrupt(scope:, span: s, request_id:)
      end
    end

    ##
    # @return [void]
    def on_exit
      @tracers.each(&:on_exit)
    end

    ##
    # @param (see LLM::Tracer#start_trace)
    # @return [Array<LLM::Tracer>]
    def start_trace(...)
      @tracers.each { _1.start_trace(...) }
    end

    ##
    # @return [Array<LLM::Tracer>]
    def stop_trace
      @tracers.each(&:stop_trace)
    end

    ##
    # @param (see LLM::Tracer#set_finish_metadata_proc)
    # @return [Array<LLM::Tracer>]
    def set_finish_metadata_proc(...)
      @tracers.each { _1.set_finish_metadata_proc(...) }
    end

    ##
    # @param (see LLM::Tracer#merge_extra)
    # @return [Array<LLM::Tracer>]
    def merge_extra(...)
      @tracers.each { _1.merge_extra(...) }
    end
  end
end
