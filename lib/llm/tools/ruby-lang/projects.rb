# frozen_string_literal: true

require_relative "../ruby-lang"

class LLM::Tool::RubyLang
  ##
  # The {LLM::Tool::RubyLang::Projects LLM::Tool::RubyLang::Projects}
  # class implements a tool that lists projects.
  #
  # It is the map a caller needs before it can narrow an
  # {LLM::Tool::RubyLang::Issues} listing: Ruby is the tree
  # at the root of bugs.ruby-lang.org and its subprojects -
  # Ruby master among them - are where the issues actually
  # sit, so `project_id:` is a number that comes from here
  # or is a guess.
  #
  # `include:` takes `trackers`, which is where the ids a
  # `tracker_id:` filter wants come from, and
  # `issue_categories`, `enabled_modules`, `time_entry_activities`
  # and `issue_custom_fields` beside it. A project is
  # returned with its identifier and its id, and the two
  # are not the same thing: the identifier is the slug in a
  # URL and the id is the number a filter takes.
  class Projects < self
    ##
    # The parts of a project that can be asked for beside it.
    # @return [Array<String>]
    INCLUDE = %w[
      trackers issue_categories enabled_modules
      time_entry_activities issue_custom_fields
    ].freeze

    name "ruby-lang-projects"
    description "List the projects on bugs.ruby-lang.org\n" \
                "This request is a GET of /projects.json"
    parameter :include, Array[String], "the parts to read beside each project, eg trackers"
    parameter :limit, Integer, "the max number of projects to return (100 at most)"
    parameter :offset, Integer, "the number of projects to skip, for the next page"
    parameter :timeout, Integer, "the maximum allowed time for the request to run (in seconds)"
    defaults include: [], limit: 100, offset: 0, timeout: 30

    ##
    # @param [Array<String>] include
    #  One or more of {INCLUDE}
    # @param [Integer] limit
    #  The max number of projects to return
    # @param [Integer] offset
    #  The number of projects to skip
    # @param [Integer] timeout
    #  The max number of seconds to wait for the response
    # @return [Hash]
    def call(include: [], limit: 100, offset: 0, timeout: 30)
      validate!(include:, limit:, offset:)
      get("/projects.json", {include:, limit:, offset:}, timeout:)
    end

    private

    ##
    # @api private
    def validate!(include:, limit:, offset:)
      if Array(include).any? { |part| !INCLUDE.include?(part.to_s) }
        raise RuntimeError, "include must be one of: #{INCLUDE.join(', ')}"
      elsif !(::Integer === limit) || limit < 1 || limit > 100
        raise RuntimeError, "limit must be between 1 and 100"
      elsif !(::Integer === offset) || offset < 0
        raise RuntimeError, "offset must be zero or more"
      end
    end
  end
end
