# frozen_string_literal: true

class LLM::Tool::Git
  ##
  # The {LLM::Tool::Git::Show} class implements
  # a tool that shows the objects a commit, tag,
  # or tree holds.
  class Show < self
    name "git-show"
    description "Show the objects a revision holds"
    parameter :rev, String, "a revision, defaults to HEAD"
    parameter :path, String, "only show this path"
    parameter :stat, Boolean, "show a diffstat instead of a patch"
    defaults rev: "HEAD", path: nil, stat: false

    ##
    # @param [String] rev
    #  A revision
    # @param [String, nil] path
    #  An optional path
    # @param [Boolean] stat
    #  Whether to show a diffstat instead of a patch
    # @return [Hash]
    def call(rev: "HEAD", path: nil, stat: false)
      Exec
        .new(env:)
        .call(arguments: parse!(rev:, path:, stat:))
    end

    private

    ##
    # @api private
    def parse!(rev:, path:, stat:)
      arguments = ["show"]
      arguments << "--stat" if stat
      arguments << rev
      arguments += ["--", path] if path
      arguments
    end
  end
end
