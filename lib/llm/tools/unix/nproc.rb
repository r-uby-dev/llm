# frozen_string_literal: true

class LLM::Tool::Unix
  ##
  # The {LLM::Tool::Unix::Nproc} class implements
  # a tool that prints the number of processing units
  # available to the current process.
  class Nproc < self
    name "nproc"
    description "Print the number of processing units available to the current process"
    parameter :timeout, Integer, "the maximum allowed time for nproc to run (in seconds)"
    defaults timeout: DEFAULT_TIMEOUT

    ##
    # @param [Integer] timeout
    #  The maximum time to allow nproc to run, in seconds
    # @return [Hash]
    def call(timeout: DEFAULT_TIMEOUT)
      exec(command: "nproc", arguments: [*parse!], timeout:)
    end

    private

    ##
    # @api private
    def parse!
      ["--"]
    end
  end
end
