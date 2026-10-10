# frozen_string_literal: true

class LLM::Tracer
  ##
  # The {LLM::Tracer::Rescue} module prepends
  # itself to every subclass of {LLM::Tracer}
  # and ensures that a tracer callback never
  # crashes an agent.
  #
  # When an error occurs, it is dumped to standard
  # error and does not travel up the stack. But
  # LLM::Interrupt, and any other exception not
  # covered by the 'ERRORS' constant can crash
  # the tracer. So it handles most cases but not
  # all, and LLM::Interrupt travelling up the stack
  # is intentional.
  module Rescue
    ##
    # @param [StandardError] ex
    # @return [void]
    def self.crash(tracer, ex)
      $stderr.puts "",
                   "an llm.rb tracer has crashed.",
                   "",
                   "[  tracer    ] #{tracer.class}",
                   "[  class     ] #{ex.class}",
                   "[  message   ] #{ex.message}",
                   "[  backtrace ] ",
                   "#{(ex.backtrace || []).take(10).join("\n")}",
                   ""
    end

    ##
    # @api private
    ERRORS = [StandardError, ScriptError]
    private_constant :ERRORS

    def on_exit
      super
    rescue LLM::Interrupt
      raise
    rescue *ERRORS => ex
      LLM::Tracer::Rescue.crash(self, ex)
    end

    def on_request_start(...)
      super
    rescue LLM::Interrupt
      raise
    rescue *ERRORS => ex
      LLM::Tracer::Rescue.crash(self, ex)
    end

    def on_request_finish(...)
      super
    rescue LLM::Interrupt
      raise
    rescue *ERRORS => ex
      LLM::Tracer::Rescue.crash(self, ex)
    end

    def on_request_error(...)
      super
    rescue LLM::Interrupt
      raise
    rescue *ERRORS => ex
      LLM::Tracer::Rescue.crash(self, ex)
    end

    def on_tool_start(...)
      super
    rescue LLM::Interrupt
      raise
    rescue *ERRORS => ex
      LLM::Tracer::Rescue.crash(self, ex)
    end

    def on_tool_interrupt(...)
      super
    rescue LLM::Interrupt
      raise
    rescue *ERRORS => ex
      LLM::Tracer::Rescue.crash(self, ex)
    end

    def on_tool_finish(...)
      super
    rescue LLM::Interrupt
      raise
    rescue *ERRORS => ex
      LLM::Tracer::Rescue.crash(self, ex)
    end

    def on_tool_error(...)
      super
    rescue LLM::Interrupt
      raise
    rescue *ERRORS => ex
      LLM::Tracer::Rescue.crash(self, ex)
    end

    def on_interrupt(...)
      super
    rescue LLM::Interrupt
      raise
    rescue *ERRORS => ex
      LLM::Tracer::Rescue.crash(self, ex)
    end
  end
end
