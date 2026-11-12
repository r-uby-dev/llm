# frozen_string_literal: true

require_relative "../unix"

class LLM::Tool::Unix
  ##
  # The {LLM::Tool::Unix::Mkdir LLM::Tool::Unix::Mkdir} class implements
  # a tool that can create a tree of new directories.
  class Mkdir < self
    require_relative "../exec"

    name "mkdir"
    description "Create a new directory\n" \
                "This command (mkdir) is spawned without a shell"
    parameter :path, String, "the path to the directory"
    parameter :max_bytes, Integer, "max number of bytes to emit"
    required %i[path]
    defaults max_bytes: -> { Exec.max_bytes }

    ##
    # @param [String] path
    # @return [Hash]
    def call(path:, max_bytes: Exec.max_bytes)
      Exec.new.call(
        command: "mkdir",
        arguments: ["-p", path],
        max_bytes:
      )
    end
  end
end
