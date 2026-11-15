# frozen_string_literal: true

require_relative "../ruby-lang"

class LLM::Tool::RubyLang
  ##
  # The {LLM::Tool::RubyLang::Issues LLM::Tool::RubyLang::Issues}
  # class implements a tool that lists issues.
  #
  # It is the search that has to come before
  # {LLM::Tool::RubyLang::Issue}: a model that is asked about
  # a bug nobody gave a number for needs the number first,
  # and `subject:` is how it finds one by what the title
  # says. Redmine matches it as a substring, which is the
  # `subject=~` filter written as a parameter.
  #
  # The filters are Redmine's own. `status:` is `open`,
  # `closed`, or `*` for either, and it is the one that
  # matters most: the default is `open`, so a listing does
  # not bury the live bugs under the closed ones. `tracker_id:`
  # separates a Bug from a Feature, `author_id:` and
  # `assigned_to_id:` name a person by id, and `project_id:`
  # narrows the listing to one subproject - the ids come
  # from {LLM::Tool::RubyLang::Projects} and from the
  # `trackers` it includes.
  #
  # `sort:` is a field and a direction, `updated_on:desc` by
  # default, which is the order a model wants when it is
  # catching up. `limit:` is 25 unless it is given and `offset:`
  # is how a page is walked; Redmine caps a page at 100, and
  # the answer carries `total_count` beside `issues`, so a
  # caller knows how many pages there are.
  class Issues < self
    ##
    # The status groups Redmine accepts as a keyword.
    # @return [Array<String>]
    STATUS = %w[open closed *].freeze

    ##
    # The parts of each issue that can be asked for.
    # @return [Array<String>]
    INCLUDE = %w[
      journals attachments relations children changesets
      allowed_statuses watchers
    ].freeze

    name "ruby-lang-issues"
    description "List or search the issues on bugs.ruby-lang.org\n" \
                "This request is a GET of /issues.json"
    parameter :status, Enum[*STATUS], "the status group to list: open, closed or * for either"
    parameter :subject, String, "only the issues whose subject contains this text"
    parameter :project_id, Integer, "only the issues of this project, by id"
    parameter :tracker_id, Integer, "only the issues of this tracker, by id"
    parameter :author_id, Integer, "only the issues this user opened, by id"
    parameter :assigned_to_id, Integer, "only the issues assigned to this user, by id"
    parameter :include, Array[String], "the parts to read beside each issue, eg journals"
    parameter :sort, String, "the field and direction to sort by, eg updated_on:desc"
    parameter :limit, Integer, "the max number of issues to return (100 at most)"
    parameter :offset, Integer, "the number of issues to skip, for the next page"
    parameter :timeout, Integer, "the maximum allowed time for the request to run (in seconds)"
    defaults status: "open", subject: nil, project_id: nil, tracker_id: nil,
             author_id: nil, assigned_to_id: nil, include: [],
             sort: "updated_on:desc", limit: 25, offset: 0, timeout: 30

    ##
    # @param [String] status
    #  The status group to list, one of {STATUS}
    # @param [String, nil] subject
    #  Only the issues whose subject contains this text
    # @param [Integer, nil] project_id
    #  Only the issues of this project
    # @param [Integer, nil] tracker_id
    #  Only the issues of this tracker
    # @param [Integer, nil] author_id
    #  Only the issues this user opened
    # @param [Integer, nil] assigned_to_id
    #  Only the issues assigned to this user
    # @param [Array<String>] include
    #  One or more of {INCLUDE}
    # @param [String] sort
    #  The field and direction to sort by
    # @param [Integer] limit
    #  The max number of issues to return
    # @param [Integer] offset
    #  The number of issues to skip
    # @param [Integer] timeout
    #  The max number of seconds to wait for the response
    # @return [Hash]
    def call(status: "open", subject: nil, project_id: nil, tracker_id: nil,
             author_id: nil, assigned_to_id: nil, include: [], sort: "updated_on:desc",
             limit: 25, offset: 0, timeout: 30)
      validate!(status:, subject:, project_id:, tracker_id:, author_id:,
                assigned_to_id:, include:, sort:, limit:, offset:)
      get(
        "/issues.json",
        {
          status_id: status,
          subject: subject && "~#{subject}",
          project_id:,
          tracker_id:,
          author_id:,
          assigned_to_id:,
          include:,
          sort:,
          limit:,
          offset:
        },
        timeout:
      )
    end

    private

    ##
    # @api private
    def validate!(status:, subject:, project_id:, tracker_id:, author_id:,
                  assigned_to_id:, include:, sort:, limit:, offset:)
      ids = {project_id:, tracker_id:, author_id:, assigned_to_id:}
      if !STATUS.include?(status.to_s)
        raise RuntimeError, "status must be one of: #{STATUS.join(', ')}"
      elsif subject && subject.to_s.empty?
        raise RuntimeError, "a subject can't be empty"
      elsif ids.any? { |_, id| id && (!(::Integer === id) || id < 1) }
        raise RuntimeError, "an id must be a positive integer"
      elsif Array(include).any? { |part| !INCLUDE.include?(part.to_s) }
        raise RuntimeError, "include must be one of: #{INCLUDE.join(', ')}"
      elsif !/\A[a-z_]+(:(asc|desc))?(,[a-z_]+(:(asc|desc))?)*\z/.match?(sort.to_s)
        raise RuntimeError, "sort must be a field and a direction, eg updated_on:desc"
      elsif !(::Integer === limit) || limit < 1 || limit > 100
        raise RuntimeError, "limit must be between 1 and 100"
      elsif !(::Integer === offset) || offset < 0
        raise RuntimeError, "offset must be zero or more"
      end
    end
  end
end
