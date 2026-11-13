# frozen_string_literal: true

require_relative "../unix"

class LLM::Tool::Unix
  ##
  # The {LLM::Tool::Unix::Make LLM::Tool::Unix::Make}
  # class implements a tool that runs a target of a
  # Makefile.
  #
  # It is the tool that `make` earns when a project has
  # a Makefile - {LLM::Tool::Unix::Cc} compiles one file
  # and `make` builds what depends on it. `dry_run:`
  # prints the commands without running them, and
  # `always_make:` builds the target even when it looks
  # up to date, which is what a file whose timestamp is
  # in the future needs.
  #
  # The tool spawns `make` without a shell, from
  # `directory:` when it is given, and the target comes
  # after `--`, so a target that begins with `-` is read
  # as a target. A target or a variable that is not
  # given is the first target of the Makefile, and
  # `$MAKEFLAGS` is not consulted. The output of a build
  # can be more than a model can read, so
  # {LLM::Tool::Utils::Process#exec} stops reading at
  # `max_bytes:` and says that it truncated.
  class Make < self
    name "make"
    description "Run a target of a Makefile\n" \
                "This command (make) is spawned without a shell"
    parameter :target, String, "the target to build (default is the first target of the Makefile)"
    parameter :directory, String, "the directory the Makefile is in (default is cwd)"
    parameter :variables, Hash[String, String], "one or more variables to set (eg {'CC' => 'cc'})"
    parameter :dry_run, Boolean, "print the commands without running them (-n)"
    parameter :always_make, Boolean, "build the target even when it looks up to date (-B)"
    parameter :jobs, Integer, "the number of jobs to run at once (-j)"
    parameter :timeout, Integer, "the maximum allowed time for the command to run (in seconds)"
    parameter :max_bytes, Integer, "max number of bytes to emit"
    defaults target: nil, directory: nil, variables: {}, dry_run: false,
             always_make: false, jobs: nil, timeout: 60, max_bytes: -> { max_bytes }

    ##
    # @param [String, nil] target
    #  The target to build
    # @param [String, nil] directory
    #  The directory the Makefile is in
    # @param [Hash{String => String}] variables
    #  One or more variables to set
    # @param [Boolean] dry_run
    #  Print the commands without running them
    # @param [Boolean] always_make
    #  Build the target even when it looks up to date
    # @param [Integer, nil] jobs
    #  The number of jobs to run at once
    # @param [Integer] timeout
    #  The maximum allowed time for make to run, in
    #  seconds
    # @param [Integer] max_bytes
    #  The max number of bytes to emit
    # @return [Hash]
    def call(target: nil, directory: nil, variables: {}, dry_run: false,
             always_make: false, jobs: nil, timeout: 60,
             max_bytes: self.class.max_bytes)
      validate!(target:, directory:, variables:, jobs:)
      res = exec(
        command: "make",
        arguments: [*arguments(target:, variables:, dry_run:, always_make:, jobs:), *[target].compact],
        timeout:,
        max_bytes:
      )
      {**res, **(directory ? {directory:} : {})}
    end

    private

    ##
    # Builds the argument vector make is given: the flags,
    # the variables, then `--`.
    # @return [Array<String>]
    def arguments(target:, variables:, dry_run:, always_make:, jobs:)
      [
        *(directory.nil? ? [] : []),
        *(dry_run ? ["-n"] : []),
        *(always_make ? ["-B"] : []),
        *(jobs ? ["-j", jobs.to_s] : []),
        *variables.map { |name, value| "#{name}=#{value}" },
        "--"
      ]
    end

    ##
    # @api private
    def validate!(target:, directory:, variables:, jobs:)
      if target && target.to_s.empty?
        raise RuntimeError, "target can't be empty"
      elsif target && target.to_s.start_with?("-")
        raise RuntimeError, "a target can't begin with '-'"
      elsif directory && !Dir.exist?(directory)
        raise RuntimeError, "directory does not exist: #{directory}"
      elsif jobs && (!(::Integer === jobs) || jobs < 1)
        raise RuntimeError, "jobs must be a positive integer"
      elsif variables && !(::Hash === variables)
        raise RuntimeError, "variables must be a Hash"
      end
    end
  end
end
