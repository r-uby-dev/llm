# frozen_string_literal: true

class LLM::Tool::Git
  ##
  # The {LLM::Tool::Git::Clone} class implements
  # a tool that clones a repository into a new
  # directory.
  class Clone < self
    name "git-clone"
    description "Clone a repository into a new directory"
    parameter :repository, String, "the repository to clone"
    parameter :directory, String, "the directory to clone into"
    parameter :timeout, Integer, "the maximum allowed time for git to run (in seconds)"
    required %i[repository]
    defaults directory: nil, timeout: DEFAULT_TIMEOUT

    ##
    # @param [String] repository
    #  The repository to clone
    # @param [String, nil] directory
    #  An optional directory to clone into. It defaults
    #  to the name of the repository
    # @param [Integer] timeout
    #  The maximum time to allow git to run, in seconds
    # @return [Hash]
    def call(repository:, directory: nil, timeout: DEFAULT_TIMEOUT, cwd: Dir.getwd)
      Exec
        .new(env:)
        .call(command: "git", arguments: ["-C", cwd, *parse!(repository:, directory:)], timeout:)
    end

    private

    ##
    # @api private
    def parse!(repository:, directory:)
      arguments = ["clone", "--", repository]
      arguments << directory if directory
      arguments
    end
  end
end
