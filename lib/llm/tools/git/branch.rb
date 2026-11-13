# frozen_string_literal: true

class LLM::Tool::Git
  ##
  # The {LLM::Tool::Git::Branch} class implements
  # a tool that lists, creates, and deletes branches.
  class Branch < self
    name "git-branch"
    description "List, create, or delete branches"
    parameter :action, Enum["list", "create", "delete"], "what to do"
    parameter :name, String, "the branch name (create and delete)"
    parameter :timeout, Integer, "the maximum allowed time for git to run (in seconds)"
    defaults action: "list", name: nil, timeout: DEFAULT_TIMEOUT

    ##
    # @param [String] action
    #  One of "list", "create", or "delete"
    # @param [String, nil] name
    #  The branch name
    # @raise [ArgumentError]
    #  When a branch name is required and not given
    # @param [Integer] timeout
    #  The maximum time to allow git to run, in seconds
    # @param [String, nil] cwd
    #  The directory git runs in
    # @return [Hash]
    def call(action: "list", name: nil, timeout: DEFAULT_TIMEOUT, cwd: nil)
      execute(
        command: "git",
        arguments: [*chdir(cwd), *parse!(action:, name:)],
        env:,
        timeout:
      )
    end

    private

    ##
    # @api private
    def parse!(action:, name:)
      case action
      when "list" then ["branch", "--list", name].compact
      when "create" then [validate_create!(action:, name:), "branch", name].tap(&:shift)
      when "delete" then [validate_delete!(action:, name:), "branch", "-d", name].tap(&:shift)
      else raise LLM::Error, "action: must be one of: list, create, delete"
      end
    end

    ##
    # @api private
    def validate_create!(action:, name:)
      if name.nil?
        raise LLM::Error, "'name' is required to create a branch"
      end
    end

    ##
    # @api private
    def validate_delete!(action:, name:)
      if name.nil?
        raise LLM::Error, "'name' is required to delete a branch"
      end
    end
  end
end
