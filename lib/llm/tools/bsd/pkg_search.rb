# frozen_string_literal: true

require_relative "../bsd"

class LLM::Tool::BSD
  ##
  # The {LLM::Tool::BSD::PkgSearch LLM::Tool::BSD::PkgSearch}
  # class implements a tool that searches the package
  # repositories.
  #
  # It is the question that comes before
  # {LLM::Tool::BSD::PkgInstall}: a model that is told to
  # add a program does not know the name of the package
  # that provides it, and `pkg search -S comment-description`
  # finds a package by what it does where `-S pkg-name`
  # finds one by what it is called. It spawns `pkg` with
  # `search` as its first argument.
  #
  # It takes one pattern, and it leaves the catalogue
  # field alone unless `field:` names one, so the default
  # is the page's: `pkg-name`, or the port origin when
  # the pattern contains a `/`. The matching is the
  # page's too - a regular expression, case sensitive -
  # and `match:` with `exact:` or `glob:` is how that
  # changes. `modifiers:` is `-Q`, repeatable, and `full`,
  # `depends-on`, `required-by`, `size`, `pkg-size`,
  # `www`, `licenses`, `options`, `categories` and
  # `repository` are the ones a build asks for.
  #
  # `raw:` (`-R`) prints the whole manifest of each match
  # instead of a line of catalogue, and `raw_format:`
  # picks `yaml` (its default), `json`, `json-compact` or
  # `ucl`; the compact JSON is one line per package and
  # the shape that parses without a second thought. The
  # result of {LLM::Tool::Utils::Process#execute} is
  # returned as it is.
  #
  # It is read-only, but `no_repo_update:` (`-U`) still
  # matters: without it `pkg` updates the repository
  # catalogue over the network before it searches.
  class PkgSearch < self
    ##
    # The fields a pattern is matched against, as `-S`
    # names them.
    # @return [Array<String>]
    FIELDS = %w[
      pkg-name name origin comment comment-description description
    ].freeze

    ##
    # The matching modes, keyed by the name a model asks
    # for. `regex` is how pkg matches a pattern when no
    # flag is given.
    # @return [Hash{String => Array<String>}]
    MATCHES = {
      "regex" => [],
      "exact" => ["-e"],
      "glob" => ["-g"]
    }.freeze

    ##
    # The formats `-R` prints a manifest in. `yaml` is
    # what pkg uses when no flag is given.
    # @return [Array<String>]
    FORMATS = %w[json json-compact ucl yaml].freeze

    name "pkg-search"
    description "Search the package repositories with pkg search (FreeBSD)\n" \
                "This command (pkg) is spawned without a shell"
    parameter :pattern, String, "the pattern to search for"
    parameter :field, Enum[*FIELDS], "the field the pattern is matched against (-S)"
    parameter :match, Enum[*MATCHES.keys], "how the pattern matches"
    parameter :case_sensitive, Boolean, "match case sensitively (-i turns this off)"
    parameter :modifiers, Array[String], "fields to add to each match, eg full, depends-on or size (-Q)"
    parameter :repositories, Array[String], "search these repositories only (-r)"
    parameter :raw, Boolean, "print the whole manifest of each match (-R)"
    parameter :raw_format, Enum[*FORMATS], "the format of a raw manifest"
    parameter :quiet, Boolean, "print less, without the label of each match (-q)"
    parameter :no_repo_update, Boolean, "do not update the repository catalogue first (-U)"
    parameter :timeout, Integer, "the maximum allowed time for the command to run (in seconds)"
    parameter :max_bytes, Integer, "max number of bytes to emit"
    required %i[pattern]
    defaults field: nil, match: "regex", case_sensitive: true, modifiers: [],
             repositories: [], raw: false, raw_format: nil, quiet: false,
             no_repo_update: false, timeout: 120, max_bytes: -> { max_bytes }

    ##
    # @param [String] pattern
    #  The pattern to search for
    # @param [String, nil] field
    #  The field the pattern is matched against, one of
    #  {FIELDS}
    # @param [String] match
    #  How the pattern matches, one of `regex`, `exact` or
    #  `glob`
    # @param [Boolean] case_sensitive
    #  Match case sensitively
    # @param [Array<String>] modifiers
    #  One or more fields to add to each match, eg `full`,
    #  `depends-on` or `size`
    # @param [Array<String>] repositories
    #  One or more repositories to search
    # @param [Boolean] raw
    #  Print the whole manifest of each match
    # @param [String, nil] raw_format
    #  The format of a raw manifest, one of {FORMATS}
    # @param [Boolean] quiet
    #  Print less, without the label of each match
    # @param [Boolean] no_repo_update
    #  Do not update the repository catalogue first
    # @param [Integer] timeout
    #  The maximum allowed time for pkg to run, in
    #  seconds
    # @param [Integer] max_bytes
    #  The max number of bytes to emit
    # @return [Hash]
    def call(pattern:, field: nil, match: "regex", case_sensitive: true, modifiers: [],
             repositories: [], raw: false, raw_format: nil, quiet: false,
             no_repo_update: false, timeout: 120, max_bytes: self.class.max_bytes)
      validate!(pattern:, field:, match:, raw:, raw_format:, modifiers:, repositories:)
      execute(
        command: "pkg",
        arguments: arguments(
          pattern:, field:, match:, case_sensitive:, modifiers:, repositories:,
          raw:, raw_format:, quiet:, no_repo_update:
        ),
        timeout:,
        max_bytes:
      )
    end

    private

    ##
    # Builds the argument vector pkg is given: the
    # subcommand, the flags, the field, the modifiers, the
    # matching mode, the repositories, then the pattern.
    # @return [Array<String>]
    def arguments(pattern:, field:, match:, case_sensitive:, modifiers:, repositories:,
                  raw:, raw_format:, quiet:, no_repo_update:)
      [
        "search",
        *(quiet ? ["-q"] : []),
        *(raw ? ["-R"] : []),
        *(raw_format ? ["--raw-format", raw_format] : []),
        *(no_repo_update ? ["-U"] : []),
        *(field ? ["-S", field] : []),
        *Array(modifiers).flat_map { |modifier| ["-Q", modifier] },
        *(case_sensitive ? [] : ["-i"]),
        *MATCHES.fetch(match.to_s),
        *Array(repositories).flat_map { |repo| ["-r", repo] },
        pattern
      ]
    end

    ##
    # @api private
    def validate!(pattern:, field:, match:, raw:, raw_format:, modifiers:, repositories:)
      if pattern.to_s.empty?
        raise RuntimeError, "pattern can't be empty"
      elsif pattern.to_s.start_with?("-")
        raise RuntimeError, "a pattern can't begin with '-'"
      elsif field && !FIELDS.include?(field.to_s)
        raise RuntimeError, "field must be one of: #{FIELDS.join(', ')}"
      elsif !MATCHES.key?(match.to_s)
        raise RuntimeError, "match must be one of: #{MATCHES.keys.join(', ')}"
      elsif raw_format && !FORMATS.include?(raw_format.to_s)
        raise RuntimeError, "raw_format must be one of: #{FORMATS.join(', ')}"
      elsif raw_format && !raw
        raise RuntimeError, "raw_format needs raw to print a manifest"
      elsif Array(modifiers).any? { _1.to_s.empty? }
        raise RuntimeError, "a modifier can't be empty"
      elsif Array(repositories).any? { _1.to_s.empty? }
        raise RuntimeError, "a repository can't be empty"
      end
    end
  end
end
