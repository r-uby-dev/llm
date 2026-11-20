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
    parameter :max_bytes, Integer, "max number of bytes to emit"
    required %i[repository]
    defaults directory: nil, timeout: DEFAULT_TIMEOUT, max_bytes: -> { max_bytes }

    ##
    # @param [String] repository
    #  The repository to clone
    # @param [String, nil] directory
    #  An optional directory to clone into. It defaults
    #  to the name of the repository
    # @param [Integer] timeout
    #  The maximum time to allow git to run, in seconds
    # @param [Integer] max_bytes
    #  The max number of bytes to emit
    # @param [String, nil] cwd
    #  The directory git runs in
    # @return [Hash]
    def call(repository:, directory: nil, timeout: DEFAULT_TIMEOUT, cwd: nil,
             max_bytes: self.class.max_bytes)
      exec(
        command: "git",
        arguments: [*chdir(cwd), *parse!(repository:, directory:)],
        env:,
        timeout:,
        max_bytes:
      )
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
