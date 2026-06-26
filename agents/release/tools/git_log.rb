# frozen_string_literal: true

class GitLog < LLM::Tool
  name "git-log"
  description "Show recent commits or commits in a revision range"
  parameter :range, String, "Optional git revision range such as v5.3.0..HEAD"
  parameter :limit, Integer, "Maximum number of commits to show"

  def call(range: nil, limit: 20)
    args = ["git", "log", "--oneline", "-n", limit.to_i.to_s]
    args << range if range && !range.empty?
    command = cmd(*args)
    {ok: command.success?, stdout: command.stdout, stderr: command.stderr, exitstatus: command.exit_status}
  end
end
