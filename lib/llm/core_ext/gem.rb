# frozen_string_literal: true

require_relative "rbconfig"

##
# Ractor-safe Gem methods.
module LLM::Gem
  RUNNING_WIN = begin
    host = RbConfig::RACTOR_CONFIG["host_os"]
    (WIN_PATTERNS.find { host =~ it } != nil)
  end
  private_constant :RUNNING_WIN

  ##
  # @return [String]
  def default_bindir
    RbConfig::RACTOR_CONFIG["bindir"]
  end

  ##
  # @return [String]
  def default_dir
    File.join(
      RbConfig::RACTOR_CONFIG["rubylibprefix"],
      "gems",
      RbConfig::RACTOR_CONFIG["ruby_version"]
    )
  end

  ##
  # @return [Boolean]
  def self.win_platform?
    RUNNING_WIN
  end

  ::Gem.singleton_class.prepend(self)
end if RbConfig.const_defined?(:RACTOR_CONFIG)
