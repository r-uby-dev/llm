# frozen_string_literal: true

class LLM::Console
  ##
  # Switches the active model for the REPL.
  # @see LLM::Console#model=
  class Model < Command
    name "model"
    description "switch the active model"
    parameter :model, String, "The model to switch to"

    ##
    # @param [String] model
    # @return [void]
    def call(model: nil)
      repl.model = model
      write [Node.new("model changed to "), Node.new(model, Color.red)]
    end

    private

    ##
    # @param [String] model
    # @return [Array<String>]
    def complete(model: nil)
      registry
        .models
        .select(&:text?)
        .select { _1.id.start_with?(model.to_s) }
        .map(&:id)
    end

    ##
    # @return [LLM::Registry]
    def registry
      agent.registry
    end
  end
end
