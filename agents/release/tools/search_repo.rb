# frozen_string_literal: true

class SearchRepo < LLM::Tool
  name "search-repo"
  description "Search the repository with ripgrep"
  parameter :pattern, String, "Pattern to search for"
  parameter :glob, String, "Optional file glob such as *.rb or spec/**"
  required %i[pattern]

  def call(pattern:, glob: nil)
    args = ["rg", "-n", pattern]
    args.concat(["-g", glob]) if glob && !glob.empty?
    args << "."
    command = cmd(*args)
    {ok: command.success?, stdout: command.stdout, stderr: command.stderr, exitstatus: command.exit_status}
  end
end
