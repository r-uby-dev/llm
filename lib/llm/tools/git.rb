# frozen_string_literal: true

class LLM::Tool
  ##
  # The superclass of all git commands.
  # @abstract
  # @see LLM::Tool::Git::Log
  # @see LLM::Tool::Git::Diff
  # @see LLM::Tool::Git::Show
  # @see LLM::Tool::Git::Status
  # @see LLM::Tool::Git::Commit
  # @see LLM::Tool::Git::Branch
  # @see LLM::Tool::Git::Checkout
  class Git < self
    abstract!
    require_relative "exec"
    require_relative "git/log"
    require_relative "git/diff"
    require_relative "git/show"
    require_relative "git/status"
    require_relative "git/commit"
    require_relative "git/branch"
    require_relative "git/checkout"

    private

    def env
      {}
    end
  end
end
