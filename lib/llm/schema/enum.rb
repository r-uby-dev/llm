# frozen_string_literal: true

class LLM::Schema
  ##
  # The {LLM::Schema::Enum LLM::Schema::Enum} class represents a
  # string value constrained to one of a fixed set of values.
  class Enum
    ##
    # Returns a string leaf constrained to the given values
    # @param [Array<String>] values
    # @raise [LLM::Error]
    #  When a value is a collection rather than a scalar
    # @return [LLM::Schema::String]
    def self.[](*values)
      if values.any? {  ::Array === it || ::Hash === it }
        raise LLM::Error, "Enum values must be scalars " \
                          "(did you mean Enum[*values]?)"
      end
      LLM::Schema::String.new.enum(*values)
    end
  end
end
