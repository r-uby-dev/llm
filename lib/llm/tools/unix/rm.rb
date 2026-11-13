# frozen_string_literal: true

class LLM::Tool::Unix
  ##
  # The {LLM::Tool::Unix::Rm} class implements a tool
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
    name "rm"
    description "Remove files, but never a directory tree"
    parameter :paths, Array[String], "one or more paths to remove"
    parameter :timeout, Integer, "the maximum allowed time for rm to run (in seconds)"
    required %i[paths]
    defaults timeout: DEFAULT_TIMEOUT

    ##
    # @param [Array<String>] paths
    #  One or more paths to remove
    # @param [Integer] timeout
    #  The maximum time to allow rm to run, in seconds
    # @raise [LLM::Error]
    #  When a path is empty, or is a flag or an absolute path
    # @return [Hash]
    def call(paths:, timeout: DEFAULT_TIMEOUT)
      exec(command: "rm", arguments: [*parse!(paths:)], timeout:)
    end

    private

    ##
    # @api private
    def parse!(paths:)
      if paths.empty?
        raise LLM::Error, "'paths' must not be empty"
      end
      paths.each { |path| validate!(path) }
      ["-f", "--", *paths]
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
