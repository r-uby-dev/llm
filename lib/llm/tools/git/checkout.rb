# frozen_string_literal: true

class LLM::Tool::Git
  ##
  # The {LLM::Tool::Git::Checkout} class implements
  # a tool that switches branches, and restores
  # working tree files.
  class Checkout < self
    name "git-checkout"
    description "Switch branches, or restore working tree files"
    parameter :ref, String, "the branch or revision to check out"
    parameter :create, Boolean, "create the branch named by ref"
    parameter :path, String, "restore this path from ref"
    required %i[ref]
    parameter :timeout, Integer, "the maximum allowed time for git to run (in seconds)"
    defaults create: false, path: nil, timeout: DEFAULT_TIMEOUT

    ##
    # @param [String] ref
    #  The branch or revision to check out
    # @param [Boolean] create
    #  Whether to create the branch named by ref
    # @param [String, nil] path
    #  An optional path to restore from ref
    # @param [Integer] timeout
    #  The maximum time to allow git to run, in seconds
    # @return [Hash]
    def call(ref:, create: false, path: nil, timeout: DEFAULT_TIMEOUT)
      Exec
        .new(env:)
        .call(arguments: ["git", *parse!(ref:, create:, path:)], timeout:)
    end

    private

    ##
    # @api private
    def parse!(ref:, create:, path:)
      case
      when path then ["checkout", ref, "--", path]
      when create then ["checkout", "-b", ref]
      else ["checkout", ref]
      end
    end
  end
end
