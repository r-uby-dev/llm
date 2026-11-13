# frozen_string_literal: true

class LLM::Tool::Bsd
  ##
  # The {LLM::Tool::Bsd::Mkdir} class implements
  # a tool that creates a directory.
  class Mkdir < self
    name "bsd-mkdir"
    description "Create a directory"
    parameter :path, String, "the directory to create"
    required %i[path]
    defaults path: nil

    ##
    # @param [String] path
    #  The directory to create
    # @return [Hash]
    def call(path:)
      if path.nil? || path.empty?
        raise LLM::Error, "'path' must not be empty"
      end
      exec(command: "mkdir", arguments: [*parse!, *path, "--"])
    end

    private

    ##
    # @api private
    def parse!
      []
    end
  end
end
