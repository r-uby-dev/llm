##
# Ractor-safe Gem methods.
module Gem
  require_relative "rbconfig"
  ##
  # @return [String]
  def self.default_bindir
    RbConfig::RACTOR_CONFIG["bindir"]
  end

  ##
  # @return [String]
  def self.default_dir
    File.join(
      RbConfig::RACTOR_CONFIG["rubylibprefix"],
      "gems",
      RbConfig::RACTOR_CONFIG["ruby_version"]
    )
  end

  ##
  # @return [String]
  def self.default_exec_format
    name = RbConfig::RACTOR_CONFIG["ruby_install_name"]
    name.sub("ruby", "%s")
  end
end if defined?(Gem)
