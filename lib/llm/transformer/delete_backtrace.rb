# frozen_string_literal: true

class LLM::Transformer
  ##
  # The {LLM::Intercept::DeleteBacktrace} class
  # removes the backtrace that the runtime includes
  # with a {LLM::Function::Return} that represents
  # an error.
  #
  # @see LLM::Transformer
  class DeleteBacktrace < self
    ##
    # @param (see LLM::Intercept#call)
    # @return (see LLM::Intercept#call)
    def call(message:, **opts)
      case message
      when LLM::Function::Return
        message.value.delete(:backtrace) if message.error?
        message
      else
        message
      end
    end
  end
end
