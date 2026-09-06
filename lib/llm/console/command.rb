# frozen_string_literal: true

class LLM::Console
  ##
  # The {LLM::Console::Command LLM::Console::Command} class is the superclass
  # of all read-eval-print loop commands. A command has a name, and a
  # description. This basic version does not implement parameters. A
  # command is accessible via the `/` prefix: eg `/exit`.
  class Command
    UNDEFINED = Object.new
    SINGLETON = self
    private_constant :UNDEFINED, :SINGLETON

    ##
    # @param [String] str
    #  An input string
    # @return [Array<String>]
    #  An array of command names who match the input string
    def self.complete(str)
      registry.keys.select do |name|
        name.start_with?(str[1..])
      end
    end

    ##
    # @api private
    Parameter = Struct.new(:name, :type, :description, :options, :index, :value) do
      ##
      # @return [Boolean]
      def required?
        options[:required] == true
      end

      ##
      # Mark the parameter as required
      # @return [void]
      def required!
        options[:required] = true
      end

      ##
      # @return [Boolean]
      def optional?
        !required?
      end

      ##
      # Assign a parameter value - with type checks
      # @param [String] other
      # @return [void]
      def value=(other)
        raise TypeError, "#{other.class} is not a #{type}" unless type === other
        self[:value] = other
      end
    end

    ##
    # Find a command by a name, or by an input string.
    # @example find by name
    #  LLM::Console::Command.find_by(name: "exit")
    # @example find by input string
    #  LLM::Console::Command.find_by(input: "/exit")
    # @note
    #  The input string must be prefixed with "/"
    #  or it won't be matched. The match is made
    #  against the string before the first space -
    #  so "/exit foo" will match the "exit" command
    #  but "/exitnow" will not.
    # @param [String] input
    # @param [String] name
    # @return [LLM::Console::Command, nil]
    def self.find_by(input: UNDEFINED, name: UNDEFINED)
      if input != UNDEFINED
        return nil unless input[0] == "/"
        n, = input.split(" ")
        registry.values.find { n[1..] == _1.name }
      elsif name != UNDEFINED
        registry.values.find { name == _1.name }
      else
        raise ArgumentError, "provide either an input or a name"
      end
    end

    ##
    # @param [LLM::Console::Command] outer
    #  A new subclass
    # @return [void]
    def self.inherited(outer)
      LLM.lock(:inherited) do
        @registry[outer] = outer
        outer.instance_variable_set(:@parameters, {})
        outer.define_singleton_method(:inherited) do |inner|
          SINGLETON.inherited(inner)
          inner.instance_variable_set(:@name, outer.instance_variable_get(:@name))
          inner.instance_variable_set(:@description, outer.instance_variable_get(:@description))
          inner.instance_variable_set(:@parameters, outer.instance_variable_get(:@parameters))
        end
      end
    end

    ##
    # @return [Array<LLM::Console::Command]
    def self.registry
      @registry.transform_keys(&:name)
    end
    @registry = {}

    ##
    # Set or get a command name.
    # @param [String] name
    #  The command name.
    # @return [String]
    def self.name(name = UNDEFINED)
      return @name if name == UNDEFINED
      @name = name
    end

    ##
    # Set or get a command description.
    # @param [String] description
    #  The command description.
    # @return [String]
    def self.description(description = UNDEFINED)
      return @description if description == UNDEFINED
      @description = description
    end

    ##
    # @param [Symbol] name
    # @param [Class] type
    # @param [String] description
    # @param [Hash] options
    # @return [void]
    def self.parameter(name, type, description, options = {})
      @parameters[name] = Parameter.new(
        name, type,
        description, options,
        @parameters.size, nil
      )
    end

    ##
    # @return [Hash]
    def self.parameters
      @parameters
    end

    ##
    # @param [Array<Symbol>] names
    #  One or more required names
    # @return [void]
    def self.required(names)
      names.each do |name|
        if @parameters.key?(name)
          @parameters[name].required!
        else
          raise LLM::Error, "'#{name}' is not a known parameter"
        end
      end
    end

    ##
    # @return [LLM::Console]
    attr_reader :repl

    ##
    # @return [LLM::Agent]
    attr_reader :agent

    ##
    # @param [LLM::Console] console
    # @return [LLM::Console::Command]
    def initialize(repl)
      @repl = repl
      @agent = repl.agent
    end

    ##
    # Write a string to the buffer
    # @param [String] content
    # @return [void]
    def write(content)
      write_message "command(#{self.class.name})", content
    end

    ##
    # @param [String] user
    # @param [String] content
    # @return [void]
    def write_message(user, content)
      @repl.write_message(user, content)
    end

    ##
    # Display a formatted help message for this command.
    # Uses a single {#write} call to output the command name,
    # description, and parameter details.
    # @return [void]
    def self.help
      lines = []
      lines << "Command: #{name}"
      lines << "Description: #{description}"
      unless parameters.empty?
        lines << ""
        lines << "Parameters:"
        parameters.each_value do |param|
          tag = param.required? ? "(required)" : "(optional)"
          lines << "  #{param.name} [#{param.type}] - #{param.description} #{tag}"
        end
      end
      lines.join("\n")
    end

    ##
    # This method should be implemented by subclasses.
    # @raise [NotImplementedError]
    def call(...)
      raise NotImplementedError, "#{self.class}#call is not implemented"
    end

    ##
    # Completes the argument being typed. The keyword
    # arguments are the command's parameters; the non-nil
    # keyword is the active fragment. Subclasses override
    # this. Returns candidate completions.
    # @param [Hash] kwargs
    # @return [Array<String>]
    def complete(**kwargs)
      []
    end

    ##
    # @return [Hash<Symbol, Parameter>]
    def parameters
      self.class.parameters
    end

    require_relative "commands/compact"
    require_relative "commands/exit"
    require_relative "commands/help"
    require_relative "commands/model"
  end
end

##
# Convenience constant
LLM::Command = LLM::Console::Command
