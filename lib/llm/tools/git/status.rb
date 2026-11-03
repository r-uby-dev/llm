# frozen_string_literal: true

class LLM::Tool::Git
  ##
  # The {LLM::Tool::Git::Status} class implements
  # a tool that shows the status of the working tree.
  class Status < self
    name "git-status"
    description "Show the working tree status"
    parameter :path, String, "only report this path"
    defaults path: nil

    ##
    # @param [String, nil] path
    #  An optional path
    # @return [Hash]
    def call(path: nil)
      Exec
        .new(env:)
        .call(arguments: parse!(path:))
    end

    private

    ##
    # @api private
    def parse!(path:)
      arguments = ["status", "--porcelain"]
      arguments += ["--", path] if path
      arguments
    end
  end
end
