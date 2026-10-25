# frozen_string_literal: true

class LLM::Transformer
  ##
  # The {LLM::Transformer::DeleteBacktrace} class
  # removes the backtrace that the runtime includes
  # with a {LLM::Function::Return} that represents
  # an error.
  #
  # @see LLM::Transformer
  class DeleteBacktrace < self
    ##
    # @param (see LLM::Transformer#call)
    # @return (see LLM::Transformer#call)
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
