# frozen_string_literal: true

class LLM::Function
  ##
  # The {LLM::Function::Registry LLM::Function::Registry} module provides
  # shared registry behavior for functions and tools. {LLM::Tool.registry}
  # stores {LLM::Tool LLM::Tool} subclasses, including dynamically created MCP
  # tool subclasses, while {LLM::Function.registry} stores the functions
  # derived from those tools.
  #
  # The registry overwrites older tool definitions with newer ones when they
  # share the same tool name. In practice, tool identity is resolved by name,
  # and LLMs generally do not allow two tools with the same name.
  #
  # Functions defined with {LLM.function} are not added to the function
  # registry, since they may be closures bound to local state. Each registry
  # decides how entries are keyed via {#registry_key}.
  module Registry
    ##
    # @api private
    def self.extended(klass)
      klass.instance_variable_set(:@__registry, {})
      klass.instance_variable_set(:@__names, {})
      klass.instance_variable_set(:@__monitor, Monitor.new)
    end

    ##
    # Returns all registered entries.
    # @return [Array<LLM::Function, LLM::Tool>]
    def registry
      lock do
        @__registry.values
      end
    end

    ##
    # Finds a registered entry by name.
    # @param [String] name
    # @return [LLM::Function, LLM::Tool, nil]
    def find_by_name(name)
      lock do
        @__names[name.to_s] ||= @__registry.each_value.find do
          tool_name(_1).to_s == name.to_s
        end
      end
    end

    ##
    # Clears the registry.
    # @return [void]
    def clear_registry!
      lock do
        @__registry.clear
        @__names.clear
        nil
      end
    end

    ##
    # Registers an entry.
    # @param [LLM::Function, LLM::Tool] entry
    # @api private
    def register(entry)
      lock do
        @__registry[registry_key(entry)] = entry
        @__names[tool_name(entry).to_s] = entry if tool_name(entry)
      end
    end

    ##
    # Unregisters an entry.
    # @param [LLM::Function, LLM::Tool] entry
    # @api private
    def unregister(entry)
      lock do
        @__registry.delete(registry_key(entry))
        @__registry.delete(entry)
        @__names.delete(tool_name(entry).to_s) if tool_name(entry)
      end
    end

    ##
    # Returns the storage key for an entry.
    # @param [LLM::Function, LLM::Tool] entry
    # @return [Class<LLM::Tool>, String, nil]
    # @api private
    def registry_key(entry)
      tool_name(entry) ? entry.name : entry
    end

    ##
    # Returns the tool name, or nil for tools that are not fully initialized.
    # @param [LLM::Function, LLM::Tool] entry
    # @return [String, nil]
    # @api private
    def tool_name(entry)
      entry.respond_to?(:name) ? entry.name : nil
    end

    ##
    # @api private
    def lock(&)
      @__monitor ||= Monitor.new
      @__registry ||= {}
      @__names ||= {}
      @__monitor.synchronize(&)
    end
  end
end
