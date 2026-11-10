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
    include LLM::Rescue
    ##
    # @param [LLM::Function] function
    #  A function
    # @param [Hash] options
    #  An optional set of options
    def call(function:, **options)
      super
    rescue LLM::Interrupt
      raise
    rescue *ERRORS => ex
      crash(ex:)
      function.error(ex:, note: "an intercept crashed")
    end
  end
end
