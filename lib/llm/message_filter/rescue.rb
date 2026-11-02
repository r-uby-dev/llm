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
    include LLM::Rescue
    ##
    # @param [LLM::Message] message
    # @param [Hash] options
    # @return [LLM::Message]
    def call(message:, **options)
      super
    rescue LLM::Interrupt
      raise
    rescue *ERRORS => ex
      crash(ex:)
    end
  end
end
