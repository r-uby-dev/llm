# frozen_string_literal: true

class LLM::Tool::Unix
  ##
  # The {LLM::Tool::Unix::Which} class implements
  # a tool that locates a command.
  class Which < self
    name "which"
    description "Locate a command"
    parameter :name, String, "the name of the command"
    parameter :all, Boolean, "print every match, not just the first"
    parameter :timeout, Integer, "the maximum allowed time for which to run (in seconds)"
    required %i[name]
    defaults all: false, timeout: DEFAULT_TIMEOUT

    ##
    # @param [String] name
    #  The name of the command
    # @param [Boolean] all
    #  Whether to print every match
    # @param [Integer] timeout
    #  The maximum time to allow which to run, in seconds
    # @return [Hash]
    def call(name:, all: false, timeout: DEFAULT_TIMEOUT)
      exec(command: "which", arguments: [*parse!(name:, all:)], timeout:)
    end

    private

    ##
    # @api private
    def parse!(name:, all:)
      case
      when name.empty? then raise LLM::Error, "'name' must not be empty"
      when name.include?("/") then raise LLM::Error, "'name' must be a command name: #{name}"
      else all ? ["--all", "--", name] : ["--", name]
      end
    end
  end
end
