# frozen_string_literal: true

require_relative "../unix"

class LLM::Tool::Unix
  ##
  # The {LLM::Tool::Unix::Pwd LLM::Tool::Unix::Pwd}
  # class implements a tool that prints the current
  # working directory.
  #
  # It spawns `pwd` without a shell, and it gives it one
  # flag: `-L` (`physical: false`, the default) for the
  # logical path, or `-P` (`physical: true`) for the
  # physical one, with every symbolic link resolved. The
  # difference is the point of the command - `pwd -L`
  # inside `/sys/kern` prints `/sys/kern` where `pwd -P`
  # prints `/usr/src/sys/kern` - and pwd(1) assumes `-L`
  # when it is given no flag at all.
  #
  # `-L` reads $PWD, so the tool forwards it: a spawned
  # command inherits $PATH and nothing else, and without
  # $PWD `pwd -L` falls back to the physical path (the
  # BUGS section of pwd(1) says so). The result of
  # {LLM::Tool::Utils::Process#exec} is returned as it
  # is, so the path is `result[:stdout]` with the newline
  # that `pwd` writes, and a directory that was removed
  # under the process is the stderr and the exit status
  # that report it. {LLM::Tool::Pwd} answers the same
  # question with `Dir.getwd` and spawns nothing; this
  # tool is the command, for the model that asks for it.
  class Pwd < self
    name "pwd"
    description "Print the current working directory\n" \
                "This command (pwd) is spawned without a shell"
    parameter :physical, Boolean, "resolve symbolic links and print the physical path (-P)"
    parameter :max_bytes, Integer, "max number of bytes to emit"
    defaults physical: false, max_bytes: -> { max_bytes }

    ##
    # @param [Boolean] physical
    #  Resolve symbolic links and print the physical path
    # @param [Integer] max_bytes
    #  The max number of bytes to emit
    # @return [Hash]
    def call(physical: false, max_bytes: self.class.max_bytes)
      exec(
        command: "pwd",
        arguments: [physical ? "-P" : "-L"],
        env:,
        max_bytes:
      )
    end

    private

    ##
    # The environment pwd reads. $PWD is the logical
    # current working directory, and the one variable
    # `-L` needs to see.
    # @return [Hash]
    def env
      value = ENV["PWD"].to_s
      value.empty? ? {} : {"PWD" => value}
    end
  end
end
