# frozen_string_literal: true

##
# Helpers shared by the specs that run git against a temporary
# repository. The file lives below spec/support/git so that
# spec/setup.rb loads it with the other support files.
module GitHelpers
  ##
  # Returns true when a command exists on the PATH
  # @param [String] name
  # @return [Boolean]
  def command_available?(name)
    (ENV["PATH"] || "").split(File::PATH_SEPARATOR).any? do |dir|
      File.executable?(File.join(dir, name))
    end
  end

  ##
  # Initializes a repository in the current working directory with a
  # single commit that holds a file named "file.txt".
  # @return [void]
  def make_repo!
    git!("init", "-b", "main")
    git!("config", "user.email", "spec@example.com")
    git!("config", "user.name", "Spec")
    File.write("file.txt", "hello\n")
    git!("add", "file.txt")
    git!("commit", "-m", "initial")
  end

  ##
  # Writes a file, stages it, and commits it
  # @param [String] message
  #  The commit message, and the content written to the file
  # @param [String] path
  #  The path to write and commit
  # @return [void]
  def commit!(message, path = "file.txt")
    File.write(path, "#{message}\n")
    git!("add", path)
    git!("commit", "-m", message)
  end

  ##
  # Runs git, and discards its output
  # @param [Array<String>] argv
  # @return [void]
  def git!(*argv)
    system("git", *argv, out: File::NULL, err: File::NULL)
  end
end

RSpec.configure do |config|
  config.include(GitHelpers)
end
