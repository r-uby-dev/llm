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
    RbConfig::RACTOR_CONFIG["ruby_install_name"].sub("ruby", "%s")
  end

  ##
  # @return [String, nil]
  def self.vendor_dir
    if vendor_dir = ENV["GEM_VENDOR"]
      vendor_dir.dup
    elsif not RbConfig::RACTOR_CONFIG.key?("vendordir")
      nil
    else
      File.join(
        RbConfig::RACTOR_CONFIG["vendordir"],
        "gems",
        RbConfig::RACTOR_CONFIG["ruby_version"]
      )
    end
  end

  ##
  # @return [String]
  def self.user_dir
    gem_dir = File.join(user_home, ".gem")
    gem_dir = File.join(data_home, "gem") unless File.exist?(gem_dir)
    parts = [gem_dir, ruby_engine]
    version = RbConfig::RACTOR_CONFIG["ruby_version"]
    parts << version unless version.empty?
    File.join(parts)
  end
end if defined?(Gem)
