# frozen_string_literal: true

class LLM::Intercept
  ##
  # The {LLM::Intercept::Rescue} module prepends
  # itself to every subclass of {LLM::Intercept}
  # and ensures that an intercept callback never
  # crashes an agent.
  #
  # When an error occurs, it is dumped to standard
  # error and the tool call is allowed through. But
  # LLM::Interrupt, and any other exception not
  # covered by the 'ERRORS' constant can crash the
  # intercept. So it handles most cases but not
  # all, and LLM::Interrupt travelling up the stack
  # is intentional.
  module Rescue
    ##
    # @param [LLM::Intercept] intercept
    # @param [StandardError] ex
    # @return [void]
    def self.crash(intercept, ex)
      $stderr.puts "",
                   "an llm.rb intercept has crashed.",
                   "",
                   "[  intercept ] #{intercept.class}",
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

    def call(function:, **)
      super
    rescue LLM::Interrupt
      raise
    rescue *ERRORS => ex
      LLM::Intercept::Rescue.crash(self, ex)
      function.error(ex:, note: "an intercept crashed")
    end
  end
end
