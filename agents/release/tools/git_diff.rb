# frozen_string_literal: true

class GitDiff < LLM::Tool
  name "git-diff"
  description "Show git diff output, optionally limited to paths"
  parameter :target, String, "Optional git diff target such as --cached or HEAD~1..HEAD"
  parameter :paths, Array[String], "Optional list of paths to limit the diff"

  def call(target: nil, paths: nil)
    args = ["git", "diff"]
    args << target if target && !target.empty?
    args.concat(Array(paths)) if paths
    command = cmd(*args)
    {ok: command.success?, stdout: command.stdout, stderr: command.stderr, exitstatus: command.exit_status}
  end
end
