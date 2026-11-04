# frozen_string_literal: true

require_relative "rbconfig"

##
# Ractor-safe Gem methods.
module Gem
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
end if RbConfig.const_defined?(:RACTOR_CONFIG)
