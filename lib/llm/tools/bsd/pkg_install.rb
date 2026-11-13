# frozen_string_literal: true

require_relative "../bsd"

class LLM::Tool::BSD
  ##
  # The {LLM::Tool::BSD::PkgInstall LLM::Tool::BSD::PkgInstall}
  # class implements a tool that installs a package with
  # `pkg install`.
  #
  # It spawns `pkg install` with `-y`, so the command
  # does not stop to ask a question that nothing would
  # answer - a model that wanted a different answer would
  # have chosen a different package.
  #
  # The result of {LLM::Tool::Utils::Process#exec} is
  # returned as it is.
  class PkgInstall < self
    name "pkg-install"
    description "Install a package (FreeBSD)\n" \
                "This command (pkg install) is spawned without a shell"
    parameter :package, String, "the package to install"
    parameter :timeout, Integer, "the maximum allowed time for the command to run (in seconds)"
    parameter :max_bytes, Integer, "max number of bytes to emit"
    required %i[package]
    defaults timeout: 20, max_bytes: -> { max_bytes }

    ##
    # @param [String] package
    #  The package to install
    # @param [Integer] timeout
    #  The maximum allowed time for pkg to run, in
    #  seconds
    # @param [Integer] max_bytes
    #  The max number of bytes to emit
    # @return [Hash]
    def call(package:, timeout: 20, max_bytes: self.class.max_bytes)
      validate!(package:)
      exec(
        command: "pkg",
        arguments: ["install", "-y", package],
        timeout:,
        max_bytes:
      )
    end

    ##
    # @api private
    def validate!(package:)
      if package.to_s.empty?
        raise RuntimeError, "package can't be empty"
      elsif package.to_s.start_with?("-")
        raise RuntimeError, "a package name can't begin with '-'"
      end
    end
  end
end
