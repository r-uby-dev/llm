# frozen_string_literal: true

class LLM::Object
  ##
  # @private
  module Kernel
    TypeError = ::TypeError

    def tap(...)
      ::Kernel.instance_method(:tap).bind(self).call(...)
    end

    def instance_of?(...)
      ::Kernel.instance_method(:instance_of?).bind(self).call(...)
    end

    def extend(...)
      ::Kernel.instance_method(:extend).bind(self).call(...)
    end

    def method(...)
      ::Kernel.instance_method(:method).bind(self).call(...)
    end

    def kind_of?(klass)
      ::Kernel.instance_method(:kind_of?).bind(self).call(klass)
    end
    alias_method :is_a?, :kind_of?

    def respond_to?(m, include_private = false)
      !!SINGLETON.key(@h, m) || self.class.method_defined?(m)
    end

    def respond_to_missing?(m, include_private = false)
      !!SINGLETON.key(@h, m)
    end

    def raise(...)
      ::Kernel.raise(...)
    end

    def object_id
      ::Kernel.instance_method(:object_id).bind(self).call
    end

    def class
      ::Kernel.instance_method(:class).bind(self).call
    end

    ##
    # @return [LLM::Object]
    def freeze
      return self if frozen?
      ::Kernel.instance_method(:freeze).bind(self).call
      ::Ractor.make_shareable(self)
    end

    ##
    # @return [Boolean]
    def frozen?
      ::Kernel.instance_method(:frozen?).bind(self).call
    end

    def inspect
      "#<#{LLM::Utils.object_id(self)} properties=#{to_h.inspect}>"
    end
    alias_method :to_s, :inspect

    def pretty_print(q)
      q.text(inspect)
    end
  end
end
