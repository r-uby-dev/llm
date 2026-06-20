# frozen_string_literal: true

module LLM
  ##
  # Shared utility methods used across the runtime.
  module Utils
    extend self

    ##
    # Resolves a configured option against an object instance.
    #
    # Proc values are evaluated with `instance_exec`, symbol values are
    # optionally sent to the object as method calls, hashes are duplicated,
    # and all other values are returned as-is.
    #
    # @param [Object] obj
    # @param [Object] option
    # @param [Boolean] resolve_symbol
    # @return [Object]
    def resolve_option(obj, option, resolve_symbol: true)
      case option
      when Proc then obj.instance_exec(&option)
      when Symbol then resolve_symbol ? obj.send(option) : option
      when Hash then option.dup
      else option
      end
    end

    ##
    # Normalizes an HTTP API base path.
    #
    # Blank paths normalize to an empty string. Non-empty paths are
    # prefixed with a leading slash and stripped of trailing slashes.
    #
    # @param [String, nil] path
    # @return [String]
    def normalize_base_path(path)
      path = path.to_s.strip
      return "" if path.empty? || path == "/"
      path = "/#{path}" unless path.start_with?("/")
      path.sub(%r{/+\z}, "")
    end

    ##
    # Returns the Ruby module or class name for an object.
    #
    # This bypasses overridden `#name` implementations by binding
    # `Module#name` directly.
    #
    # @param [Module] obj
    # @return [String, nil]
    def name_of(obj)
      ::Module.instance_method(:name).bind(obj).call
    end

    ##
    # Renders the class-and-object-id portion of an inspect string.
    #
    # This returns strings like `LLM::Tool:0x1234abcd`, which can be
    # embedded into custom inspect output.
    #
    # @param [Object] obj
    # @return [String]
    def object_id(obj)
      klass = if Class === obj
        name_of(obj) || name_of(obj.superclass) || obj.class.name
      else
        obj.class.name || obj.class.to_s
      end
      "#{klass}:0x#{obj.object_id.to_s(16)}"
    end
  end
end
