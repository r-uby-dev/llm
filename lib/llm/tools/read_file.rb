# frozen_string_literal: true

class LLM::Tool
  ##
  # The {LLM::Tool::ReadFile} class implements a tool that
  # can read the contents of a file. It returns the content
  # as structured lines ({lineno:, content:}), so the model can
  # reference line numbers when requesting a narrower range.
  class ReadFile < self
    require_relative "utils"
    include Utils

    name "read-file"
    description "read the contents of a file"
    parameter :path, String, "the path to the file"
    parameter :start, Integer, "start line number"
    parameter :stop, Integer, "stop line number"
    parameter :max_bytes, Integer, "the max number of bytes to return"
    required %i[path]

    ##
    # @param [String] path
    # @param [Integer] start
    # @param [Integer] stop
    # @param [Integer] max_bytes
    # @return [Hash]
    def call(path:, start: 1, stop: -1, max_bytes: self.class.max_bytes)
      start, stop = swap_if_reversed(start, stop)
      content = read(path, start, stop)
      to_lines(content, start:, max_bytes:)
    end

    private

    ##
    # When start is greater than stop, swap them so the
    # range reads in the right direction (e.g. start: 10,
    # stop: 5 => reads lines 5-10).
    # @param [Integer] start
    # @param [Integer] stop
    # @return [[Integer, Integer]]
    def swap_if_reversed(start, stop)
      stop != -1 && start > stop ? [stop, start] : [start, stop]
    end

    ##
    # Returns the file content within the start..stop range.
    # @param [String] path
    # @param [Integer] start
    # @param [Integer] stop
    # @return [String]
    def read(path, start, stop)
      File.open(path, "r") do |f|
        cursor = 1
        while cursor < start
          f.gets
          cursor += 1
        end
        if stop == -1
          f.read
        else
          start.upto(stop).map { f.gets }.join
        end
      end
    end

    ##
    # Builds {lineno:, content:} lines from the content, capped at
    # max_bytes via the shared truncate!. The truncation marker
    # is kept out of the lines (it is not a real file line); the
    # truncated flag communicates that content was cut.
    # @param [String] content
    # @param [Integer] start
    # @param [Integer] max_bytes
    # @return [Hash]
    def to_lines(content, start:, max_bytes:)
      body, truncated = truncate!(content, max_bytes:)
      lines = body.lines.each_with_index.map do |line, index|
        {lineno: start + index, content: line}
      end
      {ok: true, lines:, truncated:}
    end
  end
end
