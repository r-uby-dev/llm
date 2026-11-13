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
  # @see LLM::Tool::Git::Grep
  class Git < self
    abstract!
    DEFAULT_TIMEOUT = 5

    require_relative "utils/process"
    include LLM::Tool::Utils::Process

    ##
    # @param [LLM::Tool::Git] klass
    # @return [void]
    def self.inherited(klass)
      klass.parameter :cwd,
                      String,
                      "the directory git runs in (default is the working directory of the command)"
      super
    end

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
    require_relative "git/grep"

    private

    ##
    # @return [Hash]
    def env
      {}
    end

    ##
    # The arguments that tell git which directory to run in.
    #
    # Without one, git runs in the working directory of the
    # command, which is not necessarily the working directory
    # of this process - a command that runs in a jail, for
    # example, has a working directory of its own.
    # @param [String, nil] cwd
    # @return [Array<String>]
    def chdir(cwd)
      cwd ? ["-C", cwd] : []
    end
  end
end
