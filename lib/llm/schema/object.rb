# frozen_string_literal: true

class LLM::Schema
  ##
  # The {LLM::Schema::Object LLM::Schema::Object} class represents an
  # object value in a JSON schema. It is a subclass of
  # {LLM::Schema::Leaf LLM::Schema::Leaf} and provides methods that
  # can act as constraints.
  class Object < Leaf
    ##
    # @return [Hash]
    attr_reader :properties

    ##
    # @param [Hash] properties
    #  A hash of properties
    # @return [LLM::Schema::Object]
    def initialize(properties)
      @properties = properties
    end

    ##
    # Get a property
    # @return [LLM::Schema::Leaf]
    def [](key)
      properties[key.to_s]
    end

    ##
    # Set a property
    # @return [void]
    def []=(key, val)
      properties[key.to_s] = val
    end

    ##
    # @return [Hash]
    def to_h
      super.merge!({type: "object", properties:, required: required_items})
    end

    ##
    # @raise [TypeError]
    #  When given an object other than Object
    # @return [LLM::Schema::Object]
    #  Returns self
    def merge!(other)
      raise TypeError, "expected #{self.class} but got #{other.class}" unless self.class === other
      @properties.merge!(other.properties)
      self
    end

    ##
    # @return [String]
    def to_json(...)
      LLM.json.dump(to_h, ...)
    end

    ##
    # @return [Array<String>]
    def keys
      @properties.keys
    end

    private

    def required_items
      @properties.filter_map {  _2.required? ? _1 : nil }
    end
  end
end
