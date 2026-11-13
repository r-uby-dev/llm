# frozen_string_literal: true

require_relative "../bsd"

class LLM::Tool::BSD
  ##
  # The {LLM::Tool::BSD::PkgInstall LLM::Tool::BSD::PkgInstall}
  # class implements a tool that installs packages.
  #
  # It spawns `pkg` with `install` as its first argument,
  # and it always passes `-y`. The command asks for
  # confirmation before it changes anything, and there is
  # nobody to answer a prompt in a spawned process, so a
  # run without it would sit there until the timeout
  # killed it. `dry_run:` is the step before a real one:
  # it prints the work-list of the packages to install,
  # upgrade and delete, sorted into dependency order,
  # without touching the system.
  #
  # `no_repo_update:` (`-U`) keeps the repository
  # catalogues as they are, where without it `pkg`
  # updates them over the network on every call.
  # `local_only:` (`-l`) goes the other way and installs
  # from local archives, which is the only mode where a
  # package argument is a path. `match:` picks how a name
  # matches - `exact`, `case-sensitive`, `glob`,
  # `case-insensitive` or `regex` - so `glob` with `zsh*`
  # is expressible without a shell. `automatic:` (`-A`)
  # and `autoremove:` (`--autoremove`) are the pair that
  # decides whether a dependency is garbage afterwards.
  #
  # The result of {LLM::Tool::Exec} is returned as it is,
  # so `pkg: No packages available to install matching
  # 'foo' have been found in the repositories` reaches the
  # model with the exit status that carries it. The tool
  # mutates the system and needs write access to the
  # package database, so the user it runs as decides
  # whether it works at all; the read-only questions -
  # what a package depends on, which package installed a
  # file, what a repository has - are `pkg info`, `pkg
  # query`, `pkg which` and `pkg search`.
  class PkgInstall < self
    require_relative "../exec"

    ##
    # The matching modes, keyed by the name a model asks
    # for. `exact` is how pkg matches a name when no flag
    # is given.
    # @return [Hash{String => Array<String>}]
    MATCHES = {
      "exact" => [],
      "case-sensitive" => ["-C"],
      "glob" => ["-g"],
      "case-insensitive" => ["-i"],
      "regex" => ["-x"]
    }.freeze

    name "pkg-install"
    description "Install packages with pkg install (FreeBSD)\n" \
                "This command (pkg) is spawned without a shell"
    parameter :packages, Array[String], "the packages to install, by name, origin or archive path"
    parameter :dry_run, Boolean, "print the work-list of the changes without making them (-n)"
    parameter :no_repo_update, Boolean, "do not update the repository catalogue first (-U)"
    parameter :quiet, Boolean, "print less, except for the work-list of a dry run (-q)"
    parameter :force, Boolean, "reinstall a package that is already installed (-f)"
    parameter :no_scripts, Boolean, "do not run the install and deinstall scripts (-I)"
    parameter :automatic, Boolean, "mark the packages as automatically installed (-A)"
    parameter :autoremove, Boolean, "remove the orphaned dependencies afterwards (--autoremove)"
    parameter :local_only, Boolean, "install from local archives and skip the repositories (-l)"
    parameter :match, String, "how names match: exact, case-sensitive, glob, case-insensitive or regex"
    parameter :repositories, Array[String], "install from these repositories only (-r)"
    parameter :timeout, Integer, "the maximum allowed time for the command to run (in seconds)"
    parameter :max_bytes, Integer, "max number of bytes to emit"
    required %i[packages]
    defaults dry_run: false, no_repo_update: false, quiet: false, force: false,
             no_scripts: false, automatic: false, autoremove: false, local_only: false,
             match: "exact", repositories: [], timeout: 300,
             max_bytes: -> { Exec.max_bytes }

    ##
    # @param [Array<String>] packages
    #  The packages to install, by name, origin or archive
    #  path
    # @param [Boolean] dry_run
    #  Print the work-list of the changes without making
    #  them
    # @param [Boolean] no_repo_update
    #  Do not update the repository catalogue first
    # @param [Boolean] quiet
    #  Print less, except for the work-list of a dry run
    # @param [Boolean] force
    #  Reinstall a package that is already installed
    # @param [Boolean] no_scripts
    #  Do not run the install and deinstall scripts
    # @param [Boolean] automatic
    #  Mark the packages as automatically installed
    # @param [Boolean] autoremove
    #  Remove the orphaned dependencies afterwards
    # @param [Boolean] local_only
    #  Install from local archives and skip the repositories
    # @param [String] match
    #  How the names match: `exact`, `case-sensitive`,
    #  `glob`, `case-insensitive` or `regex`
    # @param [Array<String>] repositories
    #  Install from these repositories only
    # @param [Integer] timeout
    #  The maximum allowed time for pkg to run, in seconds
    # @param [Integer] max_bytes
    #  The max number of bytes to emit
    # @return [Hash]
    def call(packages:, dry_run: false, no_repo_update: false, quiet: false, force: false,
             no_scripts: false, automatic: false, autoremove: false, local_only: false,
             match: "exact", repositories: [], timeout: 300, max_bytes: Exec.max_bytes)
      validate!(packages:, match:, repositories:)
      Exec.new.call(
        command: "pkg",
        arguments: arguments(
          packages:, dry_run:, no_repo_update:, quiet:, force:, no_scripts:,
          automatic:, autoremove:, local_only:, match:, repositories:
        ),
        timeout:,
        max_bytes:
      )
    end

    private

    ##
    # Builds the argument vector pkg is given: the
    # subcommand, the flags, `-y`, the matching mode, the
    # repositories, then the packages.
    # @return [Array<String>]
    def arguments(packages:, dry_run:, no_repo_update:, quiet:, force:, no_scripts:,
                  automatic:, autoremove:, local_only:, match:, repositories:)
      [
        "install",
        *(automatic ? ["-A"] : []),
        *(force ? ["-f"] : []),
        *(no_scripts ? ["-I"] : []),
        *(local_only ? ["-l"] : []),
        *(dry_run ? ["-n"] : []),
        *(quiet ? ["-q"] : []),
        *(no_repo_update ? ["-U"] : []),
        *(autoremove ? ["--autoremove"] : []),
        "-y",
        *MATCHES.fetch(match.to_s),
        *Array(repositories).flat_map { |repo| ["-r", repo] },
        *Array(packages)
      ]
    end

    ##
    # @api private
    def validate!(packages:, match:, repositories:)
      if Array(packages).empty?
        raise RuntimeError, "packages must be one or more packages"
      elsif Array(packages).any? { _1.to_s.empty? }
        raise RuntimeError, "a package can't be empty"
      elsif Array(packages).any? { _1.to_s.start_with?("-") }
        raise RuntimeError, "a package can't begin with '-'"
      elsif !MATCHES.key?(match.to_s)
        raise RuntimeError, "match must be one of: #{MATCHES.keys.join(', ')}"
      elsif Array(repositories).any? { _1.to_s.empty? }
        raise RuntimeError, "a repository can't be empty"
      end
    end
  end
end
