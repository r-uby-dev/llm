# frozen_string_literal: true

class LLM::Tool::Bsd
  ##
  # The {LLM::Tool::Bsd::Cat} class implements
  # a tool that concatenates files and prints them.
  class Cat < self
    name "bsd-cat"
    description "Concatenate files and print them to standard output"
    parameter :paths, Array[String], "one or more paths"
    defaults paths: []

    ##
    # @param [Array<String>] paths
    #  One or more paths
    # @return [Hash]
    def call(paths: [])
      if paths.empty?
        raise LLM::Error, "'paths' must not be empty"
      end
      exec(command: "cat", arguments: [*parse!, *paths, "--"])
    end

    private

    ##
    # @api private
    def parse!
      []
    end
  end
end
