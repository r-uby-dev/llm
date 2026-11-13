# frozen_string_literal: true

require_relative "../unix"

class LLM::Tool::Unix
  ##
  # The {LLM::Tool::Unix::Make LLM::Tool::Unix::Make}
  # class implements a tool that runs a build.
  #
  # It spawns `make` without a shell, and it builds the
  # argument vector itself: `-C` for the directory, `-f`
  # for the makefile, `-j` for the number of jobs, `-n`
  # and `-k` for the two flags a failed build is usually
  # read with, `-V` for the value of a variable, then the
  # `NAME=value` assignments and the targets. A build is
  # the loop an agent runs after it edits a file - run it,
  # read the failure, fix it, run it again - so the
  # directory, the targets, the variables and the flags
  # arrive as parameters instead of as an argv the model
  # has to get right on every call.
  #
  # Every flag but `-V` is shared by BSD make and GNU
  # make, so the tool works with both. `-V` is bmake's,
  # and it prints the value of a variable and builds
  # nothing, which is the second question an agent asks
  # when a Makefile misbehaves ("what would you run" is
  # the first, and `dry_run:` is how it is asked).
  class Make < self
    require_relative "../exec"

    name "make"
    description "Run make and return its output\n" \
                "This command (make) is spawned without a shell"
    parameter :targets, Array[String], "the targets to build (default is the first target)"
    parameter :directory, String, "the directory the build runs in (default is cwd)"
    parameter :makefile, String, "the makefile to read instead of the default Makefile"
    parameter :assignments, Array[String], "NAME=value pairs for make"
    parameter :jobs, Integer, "the max number of jobs to run at once"
    parameter :dry_run, Boolean, "print the commands instead of running them"
    parameter :keep_going, Boolean, "keep building targets that do not depend on a failure"
    parameter :variable, String, "print the value of a variable and build nothing (bmake)"
    parameter :timeout, Integer, "the maximum allowed time for the command to run (in seconds)"
    parameter :max_bytes, Integer, "max number of bytes to emit"
    defaults targets: [], directory: nil, makefile: nil, assignments: [],
             jobs: nil, dry_run: false, keep_going: false, variable: nil,
             timeout: 120, max_bytes: -> { Exec.max_bytes }

    ##
    # @param [Array<String>] targets
    #  The targets to build
    # @param [String, nil] directory
    #  The directory the build runs in
    # @param [String, nil] makefile
    #  The makefile to read instead of the default
    #  `Makefile`
    # @param [Array<String>] assignments
    #  One or more `NAME=value` pairs
    # @param [Integer, nil] jobs
    #  The max number of jobs to run at once
    # @param [Boolean] dry_run
    #  Print the commands instead of running them
    # @param [Boolean] keep_going
    #  Keep building targets that do not depend on a
    #  failure
    # @param [String, nil] variable
    #  Print the value of a variable and build nothing
    # @param [Integer] timeout
    #  The maximum allowed time for make to run, in
    #  seconds
    # @param [Integer] max_bytes
    #  The max number of bytes to emit
    # @return [Hash]
    def call(targets: [], directory: nil, makefile: nil, assignments: [], jobs: nil,
             dry_run: false, keep_going: false, variable: nil,
             timeout: 120, max_bytes: Exec.max_bytes)
      validate!(directory:, jobs:, variable:, assignments:, targets:)
      Exec.new.call(
        command: "make",
        arguments: arguments(
          directory:, makefile:, jobs:, dry_run:, keep_going:, variable:, assignments:, targets:
        ),
        timeout:,
        max_bytes:
      )
    end

    private

    ##
    # Builds the argument vector make is given: the
    # directory, the makefile, the flags, the variable,
    # then the assignments and the targets, which make
    # reads as targets to build.
    # @return [Array<String>]
    def arguments(directory:, makefile:, jobs:, dry_run:, keep_going:, variable:, assignments:, targets:)
      [
        *(directory ? ["-C", directory] : []),
        *(makefile ? ["-f", makefile] : []),
        *(jobs ? ["-j", jobs.to_s] : []),
        *(dry_run ? ["-n"] : []),
        *(keep_going ? ["-k"] : []),
        *(variable ? ["-V", variable] : []),
        *Array(assignments),
        *Array(targets)
      ]
    end

    ##
    # @api private
    def validate!(directory:, jobs:, variable:, assignments:, targets:)
      if directory && !Dir.exist?(directory)
        raise RuntimeError, "directory does not exist: #{directory}"
      elsif jobs && (!(::Integer === jobs) || jobs < 1)
        raise RuntimeError, "jobs must be a positive integer"
      elsif variable && !variable.to_s.match?(%r{\A[A-Za-z_.][A-Za-z0-9_.]*\z})
        raise RuntimeError, "variable must be the name of a make variable"
      elsif Array(assignments).any? { !_1.to_s.match?(%r{\A[A-Za-z_.][A-Za-z0-9_.]*=}) }
        raise RuntimeError, "assignments must be NAME=value pairs"
      elsif Array(targets).any? { _1.to_s.start_with?("-") }
        raise RuntimeError, "a target can't begin with '-'"
      end
    end
  end
end
