# frozen_string_literal: true

class LLM::Tool
  ##
  # The {LLM::Tool::NotFound} tool is an
  # internal the tool the runtime uses to
  # represent a tool the model requested
  # but is not known to the runtime.
  #
  # The tool has the same name the model
  # requested, and when the tool is called
  # it will return an in-band error.
  #
  # Ractor-safe.
  #
  # @api private
  # @return [LLM::Function]
  def self.NotFound(name:)
    klass = Class.new(LLM::Tool)
    klass.name(name)
    klass.class_eval <<~STR, __FILE__, 1
      def call
        raise LLM::NoSuchToolError, "tool '#{name}' does not exist"
      end
    STR
    klass.function
  end
end
