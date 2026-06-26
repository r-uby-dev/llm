# frozen_string_literal: true

class GitStatus < LLM::Tool
  name "git-status"
  description "Show the current git status for the repository"

  def call
    command = cmd("git", "status", "--short")
    {ok: command.success?, stdout: command.stdout, stderr: command.stderr, exitstatus: command.exit_status}
  end
end
