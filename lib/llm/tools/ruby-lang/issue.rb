# frozen_string_literal: true

require_relative "../ruby-lang"

class LLM::Tool::RubyLang
  ##
  # The {LLM::Tool::RubyLang::Issue LLM::Tool::RubyLang::Issue}
  # class implements a tool that reads one issue.
  #
  # It is the call that follows a number somebody quoted:
  # what the bug says, who opened it, where it sits, and -
  # with `include: ["journals"]` - what everyone said about
  # it since. A journal is a note and a set of changes at
  # the same time, so `notes` is what was written and
  # `details` is the field edits beside it: the status that
  # moved, the assignee that changed, the backport that was
  # decided. That is the difference between the issue as it
  # stands today and the argument that got it there.
  #
  # `include:` also takes `attachments` (the patch that was
  # posted, as an id and a filename, where the bytes are
  # `/attachments/download/:id/:name`), `relations` (the
  # duplicates, the blocks, the relates), `children` (the
  # subtasks), `changesets` (the commits Redmine matched to
  # the issue), `allowed_statuses` and `watchers`.
  #
  # The description and the notes come back as Redmine
  # markup, not HTML, and nothing here renders them. An
  # issue that is private, or one that does not exist, is a
  # 404 to an anonymous caller, and both look the same.
  class Issue < self
    ##
    # The parts of an issue that can be asked for beside it.
    # @return [Array<String>]
    INCLUDE = %w[
      journals attachments relations children changesets
      allowed_statuses watchers
    ].freeze

    name "ruby-lang-issue"
    description "Read one issue from bugs.ruby-lang.org by number\n" \
                "This request is a GET of /issues/:id.json"
    parameter :id, Integer, "the issue number, eg 1"
    parameter :include, Array[String], "the parts to read beside it, eg journals or attachments"
    parameter :timeout, Integer, "the maximum allowed time for the request to run (in seconds)"
    required %i[id]
    defaults include: [], timeout: 30

    ##
    # @param [Integer] id
    #  The issue number
    # @param [Array<String>] include
    #  One or more of {INCLUDE}
    # @param [Integer] timeout
    #  The max number of seconds to wait for the response
    # @return [Hash]
    def call(id:, include: [], timeout: 30)
      validate!(id:, include:)
      get("/issues/#{id}.json", {include:}, timeout:)
    end

    private

    ##
    # @api private
    def validate!(id:, include:)
      if !(::Integer === id) || id < 1
        raise RuntimeError, "an id must be a positive integer"
      elsif Array(include).any? { |part| !INCLUDE.include?(part.to_s) }
        raise RuntimeError, "include must be one of: #{INCLUDE.join(', ')}"
      end
    end
  end
end
