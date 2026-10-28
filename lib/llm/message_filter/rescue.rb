# frozen_string_literal: true

class LLM::MessageFilter
  ##
  # The {LLM::MessageFilter::Rescue} module prepends
  # itself to every subclass of {LLM::MessageFilter}
  # and ensures that a MessageFilter callback never
  # crashes an agent.
  #
  # When an error occurs, it is dumped to standard
  # error and does not travel up the stack. But
  # LLM::Interrupt, and any other exception not
  # covered by the 'ERRORS' constant can crash
  # the filter. So it handles most cases but not
  # all, and LLM::Interrupt travelling up the stack
  # is intentional.
  module Rescue
    ##
    # @param [StandardError] ex
    # @return [void]
    def self.crash(filter, ex)
      $stderr.puts "",
                   "an llm.rb filter has crashed.",
                   "",
                   "[  MessageFilter    ] #{filter.class}",
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

    ##
    # @param [LLM::Message] message
    # @param [Hash] options
    # @return [LLM::Message]
    def call(message:, **options)
      super
    rescue LLM::Interrupt
      raise
    rescue *ERRORS => ex
      LLM::MessageFilter::Rescue.crash(self, ex)
    end
  end
end
