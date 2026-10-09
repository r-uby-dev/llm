# frozen_string_literal: true

class LLM::Function
  ##
  # The {LLM::Function::Tracing LLM::Function::Tracing} module patches
  # an LLM function (or tool) in order to add tracing support.
  module Tracing
    def call(...)
      return super unless @tracer
      span = @tracer.on_tool_start(id:, name:, arguments:, model:)
      result = super
      @tracer.on_tool_finish(result:, span:)
      result
    rescue LLM::Interrupt => ex
      @tracer&.on_tool_interrupt(ex:, span:)
      raise
    rescue => ex
      @tracer&.on_tool_error(ex:, span:)
      raise(ex)
    end
  end
end
