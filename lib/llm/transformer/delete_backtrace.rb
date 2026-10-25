# frozen_string_literal: true

class LLM::Transformer
  ##
  # The {LLM::Transformer::DeleteBacktrace} class
  # removes the backtrace that the runtime includes
  # with a {LLM::Function::Return} that represents
  # an unrescued exception raised by a tool.
  #
  # @see LLM::Transformer
  class DeleteBacktrace < self
    ##
    # @param (see LLM::Transformer#call)
    # @return (see LLM::Transformer#call)
    def call(message:, **opts)
      returns = [*message.content].flatten.grep(LLM::Function::Return)
      returns.each do
        next unless it.error?
        it.value.delete(:backtrace)
      end
      message
    end
  end
end
