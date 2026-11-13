# frozen_string_literal: true

class LLM::Tool::Unix
  ##
  # The {LLM::Tool::Unix::Cat} class implements
  # a tool that concatenates files and prints them.
  class Cat < self
    name "cat"
    description "Concatenate files and print them to standard output"
    parameter :paths, Array[String], "one or more paths"
    parameter :number, Boolean, "number the output lines"
    parameter :timeout, Integer, "the maximum allowed time for cat to run (in seconds)"
    required %i[paths]
    defaults number: false, timeout: DEFAULT_TIMEOUT

    ##
    # @param [Array<String>] paths
    #  One or more paths
    # @param [Boolean] number
    #  Whether to number the output lines
    # @param [Integer] timeout
    #  The maximum time to allow cat to run, in seconds
    # @return [Hash]
    def call(paths:, number: false, timeout: DEFAULT_TIMEOUT)
      exec(command: "cat", arguments: [*parse!(paths:, number:), "--", *paths], timeout:)
    end

    private

    ##
    # @api private
    def parse!(paths:, number:)
      if paths.any?
        arguments = []
        arguments << "-n" if number
        arguments
      else
        raise LLM::Error, "'paths' must not be empty"
      end
    end
  end
end
