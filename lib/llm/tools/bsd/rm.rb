# frozen_string_literal: true

class LLM::Tool::Bsd
  ##
  # The {LLM::Tool::Bsd::Rm} class implements a tool
  # that removes files. It never removes a directory
  # tree.
  #
  # @note
  #  This is an unguarded write tool: included, it can
  #  delete files in any directory the process can reach
  #  and a model decides which files those are. When that
  #  is not wanted the repository tools are given an
  #  `env:` of their own and {LLM::Tool::Utils::Process#run}
  #  is pointed at a sandbox.
  class Rm < self
    name "bsd-rm"
    description "Remove files, but never a directory tree"
    parameter :paths, Array[String], "one or more paths to remove"
    defaults paths: []

    ##
    # @param [Array<String>] paths
    #  One or more paths to remove
    # @raise [LLM::Error]
    #  When a path is empty, or is a flag or an absolute path
    # @return [Hash]
    def call(paths: [])
      if paths.empty?
        raise LLM::Error, "'paths' must not be empty"
      end
      paths.each { |path| validate!(path) }
      exec(command: "rm", arguments: [*parse!, *paths, "--"])
    end

    private

    ##
    # @api private
    def parse!
      ["-f"]
    end

    ##
    # @api private
    def validate!(path)
      if path.empty?
        raise LLM::Error, "'paths' must not contain an empty path"
      elsif path.start_with?("-")
        raise LLM::Error, "'paths' must not contain a flag: #{path}"
      elsif path.start_with?("/")
        raise LLM::Error, "'paths' must be relative to the working directory: #{path}"
      end
    end
  end
end
