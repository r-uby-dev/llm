# frozen_string_literal: true

require_relative "rbconfig"

##
# Ractor-safe Gem methods.
module LLM::Gem
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
  ::Gem.singleton_class.prepend(self)
end if RbConfig.const_defined?(:RACTOR_CONFIG)
