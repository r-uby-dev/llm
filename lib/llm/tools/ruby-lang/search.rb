# frozen_string_literal: true

require_relative "../ruby-lang"

class LLM::Tool::RubyLang
  ##
  # The {LLM::Tool::RubyLang::Search LLM::Tool::RubyLang::Search}
  # class implements a tool that searches the site.
  #
  # It is the one call that searches the descriptions and
  # the journals as well as the titles, where
  # {LLM::Tool::RubyLang::Issues} filters the fields. A
  # model that is told a bug mentions `Ractor` and nothing
  # else needs this one: `scope: "issues"` runs the term
  # against every issue on the site, and each hit comes
  # back with the id of the issue it belongs to.
  #
  # The scopes are Redmine's: `issues`, `news`, `documents`,
  # `changesets`, `wiki` and `messages`, or `all` for the
  # lot. `titles_only:` narrows a search to what a title
  # says, which is faster and much blunter. `limit:` is 25
  # unless it is given and `offset:` walks the pages, both
  # of them the same as everywhere else.
  class Search < self
    ##
    # The scopes Redmine searches in.
    # @return [Array<String>]
    SCOPE = %w[all issues news documents changesets wiki messages].freeze

    name "ruby-lang-search"
    description "Search bugs.ruby-lang.org with Redmine's search index\n" \
                "This request is a GET of /search.json"
    parameter :query, String, "the words to search for"
    parameter :scope, Enum[*SCOPE], "where to search"
    parameter :titles_only, Boolean, "search the titles only, not the bodies"
    parameter :limit, Integer, "the max number of hits to return (100 at most)"
    parameter :offset, Integer, "the number of hits to skip, for the next page"
    parameter :timeout, Integer, "the maximum allowed time for the request to run (in seconds)"
    required %i[query]
    defaults scope: "issues", titles_only: false, limit: 25, offset: 0, timeout: 30

    ##
    # @param [String] query
    #  The words to search for
    # @param [String] scope
    #  Where to search, one of {SCOPE}
    # @param [Boolean] titles_only
    #  Search the titles only
    # @param [Integer] limit
    #  The max number of hits to return
    # @param [Integer] offset
    #  The number of hits to skip
    # @param [Integer] timeout
    #  The max number of seconds to wait for the response
    # @return [Hash]
    def call(query:, scope: "issues", titles_only: false, limit: 25, offset: 0, timeout: 30)
      validate!(query:, scope:, limit:, offset:)
      get("/search.json", {q: query, scope:, titles_only:, limit:, offset:}, timeout:)
    end

    private

    ##
    # @api private
    def validate!(query:, scope:, limit:, offset:)
      if query.to_s.strip.empty?
        raise RuntimeError, "query can't be empty"
      elsif !SCOPE.include?(scope.to_s)
        raise RuntimeError, "scope must be one of: #{SCOPE.join(', ')}"
      elsif !(::Integer === limit) || limit < 1 || limit > 100
        raise RuntimeError, "limit must be between 1 and 100"
      elsif !(::Integer === offset) || offset < 0
        raise RuntimeError, "offset must be zero or more"
      end
    end
  end
end
