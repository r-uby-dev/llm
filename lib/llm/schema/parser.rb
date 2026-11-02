# frozen_string_literal: true

require "uri"

class LLM::Schema
  ##
  # The {LLM::Schema::Parser LLM::Schema::Parser} module provides
  # methods for parsing a JSON schema into {LLM::Schema::Leaf}
  # objects. It is used by {LLM::Schema LLM::Schema} to convert
  # external JSON schema definitions into the schema objects used
  # throughout llm.rb.
  module Parser
    METADATA_KEYS = %w[description default enum const].freeze

    ##
    # Parses a JSON schema into an {LLM::Schema::Leaf}.
    # @param [Hash] schema
    #  The JSON schema to parse
    # @raise [TypeError]
    #  When the schema is not supported
    # @return [LLM::Schema::Leaf]
    def parse(schema, root = nil)
      schema = normalize_schema(schema)
      root ||= schema
      schema = resolve_ref(schema, root)
      case schema["type"]
      when "object" then apply(parse_object(schema, root), schema)
      when "array" then apply(parse_array(schema, root), schema)
      when "string" then apply(parse_string(schema), schema)
      when "integer" then apply(parse_integer(schema), schema)
      when "number" then apply(parse_number(schema), schema)
      when "boolean" then apply(schema().boolean, schema)
      when "null" then apply(schema().null, schema)
      when ::Array then apply(schema().any_of(*schema["type"].map { parse(schema.except("type", *METADATA_KEYS).merge("type" => _1), root) }), schema.except("type"))
      when nil then parse_union(schema, root)
      else raise TypeError, "unsupported schema type #{schema["type"].inspect}"
      end
    end

    private

    def parse_object(schema, root)
      properties = (schema["properties"] || {})
        .transform_keys(&:to_s)
        .transform_values { parse(_1, root) }
      required = schema["required"] || []
      required.each do |key|
        next unless properties[key]
        properties[key].required
      end
      schema().object(properties)
    end

    def parse_array(schema, root)
      items = schema["items"] ? parse(schema["items"], root) : schema().null
      schema().array(items)
    end

    def parse_union(schema, root)
      return apply(schema().any_of(*schema["anyOf"].map { parse(_1, root) }), schema) if schema.key?("anyOf")
      return apply(schema().one_of(*schema["oneOf"].map { parse(_1, root) }), schema) if schema.key?("oneOf")
      return apply(schema().all_of(*schema["allOf"].map { parse(_1, root) }), schema) if schema.key?("allOf")
      return parse(infer_type(schema), root) if infer_type(schema)
      raise TypeError, "unsupported schema type #{schema["type"].inspect}"
    end

    def parse_string(schema)
      leaf = schema().string
      leaf.min(schema["minLength"]) if schema.key?("minLength")
      leaf.max(schema["maxLength"]) if schema.key?("maxLength")
      leaf
    end

    def parse_integer(schema)
      leaf = schema().integer
      leaf.min(schema["minimum"]) if schema.key?("minimum")
      leaf.max(schema["maximum"]) if schema.key?("maximum")
      leaf.multiple_of(schema["multipleOf"]) if schema.key?("multipleOf")
      leaf
    end

    def parse_number(schema)
      leaf = schema().number
      leaf.min(schema["minimum"]) if schema.key?("minimum")
      leaf.max(schema["maximum"]) if schema.key?("maximum")
      leaf.multiple_of(schema["multipleOf"]) if schema.key?("multipleOf")
      leaf
    end

    def apply(leaf, schema)
      leaf.description(schema["description"]) if schema.key?("description")
      leaf.default(schema["default"]) if schema.key?("default")
      leaf.enum(*schema["enum"]) if schema.key?("enum")
      leaf.const(schema["const"]) if schema.key?("const")
      leaf
    end

    def normalize_schema(schema)
      case schema
      when LLM::Object
        normalize_schema(schema.to_h)
      when Hash
        schema.each_with_object({}) do |(key, value), out|
          out[key.to_s] = normalize_schema(value)
        end
      when Array
        schema.map { normalize_schema(_1) }
      else
        schema
      end
    end

    def resolve_ref(schema, root)
      seen = {}
      while schema.key?("$ref")
        ref = schema["$ref"]
        raise TypeError, "unsupported schema ref #{ref.inspect}" unless ref.is_a?(::String) && ref.start_with?("#/")
        raise TypeError, "circular schema ref #{ref.inspect}" if seen[ref]
        seen[ref] = true
        pointer = ref.delete_prefix("#")
        raise TypeError, "unresolvable schema ref #{ref.inspect}" if pointer.match?(/%(?![0-9a-fA-F]{2})/)
        target = URI::DEFAULT_PARSER.unescape(pointer).split("/", -1).drop(1).reduce(root) do |node, token|
          raise TypeError, "unresolvable schema ref #{ref.inspect}" if token.match?(/~(?:[^01]|$)/)
          key = token.gsub("~1", "/").gsub("~0", "~")
          case node
          when ::Hash then node.fetch(key)
          when ::Array
            raise TypeError, "unresolvable schema ref #{ref.inspect}" unless key.match?(/\A(?:0|[1-9][0-9]*)\z/)
            node.fetch(key.to_i)
          else raise TypeError, "unresolvable schema ref #{ref.inspect}"
          end
        end
        raise TypeError, "unresolvable schema ref #{ref.inspect}" unless target.is_a?(::Hash)
        schema = normalize_schema(target).merge(schema.except("$ref"))
      end
      schema
    rescue KeyError, IndexError
      raise TypeError, "unresolvable schema ref #{ref.inspect}"
    end

    def infer_type(schema)
      if schema.key?("const")
        schema.merge("type" => type_of(schema["const"]))
      elsif schema.key?("enum")
        type = type_of(schema["enum"].first)
        return unless type && schema["enum"].all? { type_of(_1) == type }
        schema.merge("type" => type)
      elsif schema.key?("default")
        schema.merge("type" => type_of(schema["default"]))
      end
    end

    def type_of(value)
      case value
      when ::Hash then "object"
      when ::Array then "array"
      when ::String then "string"
      when ::Integer then "integer"
      when ::Float then "number"
      when ::TrueClass, ::FalseClass then "boolean"
      when ::NilClass then "null"
      end
    end
  end
end
