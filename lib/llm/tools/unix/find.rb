# frozen_string_literal: true

require_relative "../unix"

class LLM::Tool::Unix
  ##
  # The {LLM::Tool::Unix::Find LLM::Tool::Unix::Find}
  # class implements a tool that walks a file hierarchy
  # and returns the paths that match.
  #
  # It spawns `find` without a shell. The expression is
  # built from `-maxdepth`, `-type`, `-name` and
  # `-mmin`, and it targets the BSD `find` that FreeBSD
  # ships, so `max_depth:` needs the `-maxdepth`
  # extension that GNU find has as well, and that the
  # older `find` in macOS does not. Without
  # `max_depth:` the arguments are POSIX.
  #
  # Without `path:` the walk starts in the working
  # directory of the command, which is not necessarily
  # the working directory of this process.
  #
  # A walk can match a lot of paths, so the result is
  # capped twice: the command stops writing at
  # `max_bytes:`, and the tool returns at most `limit:`
  # paths, and says when it cut the list.
  class Find < self
    name "find"
    description "Walk a file hierarchy and return the paths that match\n" \
                "This command (find) is spawned without a shell"
    parameter :path, String, "the directory the walk starts in (default is the working directory of the command)"
    parameter :name, String, "a glob the last component of a path must match (eg '*.rb')"
    parameter :type, Enum["f", "d", "l"], "the kind of path to return: f (file), d (directory), l (link)"
    parameter :max_depth, Integer, "how many levels below path to descend"
    parameter :newer_than, Integer, "return only paths modified in the last N minutes"
    parameter :limit, Integer, "the max number of paths to return"
    parameter :timeout, Integer, "the maximum allowed time for the command to run (in seconds)"
    parameter :max_bytes, Integer, "max number of bytes to emit"
    defaults name: nil, type: nil, max_depth: nil, newer_than: nil, path: nil,
             limit: 200, timeout: 5, max_bytes: -> { max_bytes }

    ##
    # @param [String, nil] path
    #  The directory the walk starts in
    # @param [String, nil] name
    #  A glob that the last component of a path must
    #  match
    # @param [String, nil] type
    #  The kind of path to return - f, d or l
    # @param [Integer, nil] max_depth
    #  How many levels below path to descend
    # @param [Integer, nil] newer_than
    #  Return only paths modified in the last N minutes
    # @param [Integer] limit
    #  The max number of paths to return
    # @param [Integer] timeout
    #  The maximum allowed time for find to run, in
    #  seconds
    # @param [Integer] max_bytes
    #  The max number of bytes to emit
    # @return [Hash]
    def call(path: nil, name: nil, type: nil, max_depth: nil, newer_than: nil,
             limit: 200, timeout: 5, max_bytes: self.class.max_bytes)
      validate!(path:, max_depth:, newer_than:, limit:)
      res = exec(
        command: "find",
        arguments: arguments(path:, name:, type:, max_depth:, newer_than:),
        timeout:,
        max_bytes:
      )
      res[:ok] ? to_paths(res, limit:) : res
    end

    private

    ##
    # Builds the expression find is given. The path
    # comes first when one is given, then the primaries,
    # then the action `find` would imply anyway.
    # @return [Array<String>]
    def arguments(path:, name:, type:, max_depth:, newer_than:)
      [
        *[path].compact,
        *(max_depth ? ["-maxdepth", max_depth.to_s] : []),
        *(type ? ["-type", type] : []),
        *(name ? ["-name", name] : []),
        *(newer_than ? ["-mmin", "-#{newer_than}"] : []),
        "-print"
      ]
    end

    ##
    # Turns the paths find wrote, one per line, into a
    # list. When there are more paths than the limit
    # allows, the tool says so rather than pretending
    # the list is complete.
    # @param [Hash] res
    # @param [Integer] limit
    # @return [Hash]
    def to_paths(res, limit:)
      paths = res[:stdout].to_s.lines.map(&:chomp).reject(&:empty?)
      truncated = paths.size > limit
      paths = paths.first(limit)
      {ok: true, paths:, count: paths.size, truncated:}
    end

    ##
    # @api private
    def validate!(path:, max_depth:, newer_than:, limit:)
      if path && path == "/"
        raise RuntimeError, "you can't search from the root of the filesystem"
      elsif path && !Dir.exist?(path)
        raise RuntimeError, "path does not exist: #{path}"
      elsif max_depth && (!(::Integer === max_depth) || max_depth.negative?)
        raise RuntimeError, "max_depth must be a non-negative integer"
      elsif newer_than && (!(::Integer === newer_than) || newer_than < 1)
        raise RuntimeError, "newer_than must be a positive integer"
      elsif !(::Integer === limit) || limit < 1
        raise RuntimeError, "limit must be a positive integer"
      end
    end
  end
end
