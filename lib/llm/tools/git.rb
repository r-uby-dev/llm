# frozen_string_literal: true

class LLM::Tool
  ##
  # The superclass of all git commands.
  # @abstract
  # @see LLM::Tool::Git::Log
  # @see LLM::Tool::Git::Diff
  # @see LLM::Tool::Git::Show
  # @see LLM::Tool::Git::Status
  # @see LLM::Tool::Git::LsFiles
  # @see LLM::Tool::Git::Commit
  # @see LLM::Tool::Git::Branch
  # @see LLM::Tool::Git::Checkout
  # @see LLM::Tool::Git::Pull
  # @see LLM::Tool::Git::Clone
  # @see LLM::Tool::Git::Authors
  class Git < self
    abstract!
    DEFAULT_TIMEOUT = 5

    ##
    # @param [LLM::Tool::Git] klass
    # @return [void]
    def self.inherited(klass)
      klass.parameter :cwd,
                      String,
                      "The current working directory"
      super
    end

    require_relative "exec"
    require_relative "git/log"
    require_relative "git/diff"
    require_relative "git/show"
    require_relative "git/status"
    require_relative "git/ls-files"
    require_relative "git/commit"
    require_relative "git/branch"
    require_relative "git/checkout"
    require_relative "git/pull"
    require_relative "git/clone"
    require_relative "git/authors"

    private

    def env
      {}
    end
  end
end
