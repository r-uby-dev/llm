# frozen_string_literal: true

class LLM::Tool
  ##
  # The {LLM::Tool::DirTree} class implements a tool
  # that returns the contents of a directory and its
  # children.
  class DirTree < self
    name "dir-tree"
    description "returns the directory tree"
    parameter :path, String, "the directory path"
    parameter :depth, Integer, "the max depth"
    defaults depth: 5
    required %i[path]

    ##
    # @param [String] path
    #  The directory to walk
    # @param [Integer] depth
    #  How many levels to descend
    # @raise [RuntimeError]
    #  When the path does not exist
    # @return [Hash]
    def call(path:, depth: 5)
      raise "path does not exist: #{path}" unless Dir.exist?(path)
      {ok: true, tree: walk(path:, depth:)}
    end

    private

    ##
    # @param [String] path
    # @param [Integer] depth
    # @return [Hash]
    def walk(path:, depth:)
      return {} if depth <= 0
      Dir.children(path).sort.to_h do |entry|
        child = File.join(path, entry)
        if File.directory?(child)
          [entry, walk(path: child, depth: depth - 1)]
        else
          [entry, nil]
        end
      end
    end
  end
end
