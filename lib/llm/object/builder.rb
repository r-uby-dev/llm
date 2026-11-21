# frozen_string_literal: true

class LLM::Object
  ##
  # @private
  module Builder
    ##
    # @example
    #   obj = LLM::Object.from(person: {name: 'John'})
    #   obj.person.name  # => 'John'
    #   obj.person.class # => LLM::Object
    # @param [Hash, LLM::Object, Array] obj
    #   A Hash object
    # @return [LLM::Object]
    #   An LLM::Object object initialized by visiting `obj` with recursion
    def from(obj)
      case obj
      when self then from(obj.to_h)
      when Array then obj.map { |v| from(v) }
      when Hash then new(obj.each_with_object({}) { |(k, v), h| h[k] = visit(v) })
      when String, Symbol, Numeric, TrueClass, FalseClass, NilClass then obj
      else
        visited = {}
        obj.each { visited[_1] = visit(_2) }
        new(visited)
      end
    end

    private

    def visit(value)
      case value
      when self then from(value.to_h)
      when Hash then from(value)
      when Array then value.map { |v| visit(v) }
      else value
      end
    end
  end
end
