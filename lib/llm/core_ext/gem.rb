# frozen_string_literal: true

require_relative "rbconfig"

##
# Ractor-safe Gem methods.
module LLM::Gem
  ##
  # @api private
  RACTOR_CONFIG = LLM::RbConfig::RACTOR_CONFIG

  ##
  # @api private
  WINDOWS = begin
    host = RACTOR_CONFIG["host_os"]
    (::Gem::WIN_PATTERNS.find { host =~ it } != nil)
  end

  ##
  # @return [String]
  def default_bindir
    RACTOR_CONFIG["bindir"]
  end

  ##
  # @return [String]
  def default_dir
    File.join(
      RACTOR_CONFIG["rubylibprefix"],
      "gems",
      RACTOR_CONFIG["ruby_version"]
    )
  end

  ##
  # @return [Boolean]
  def win_platform?
    WINDOWS
  end

  ::Gem.singleton_class.prepend(self)
end unless defined?(Gem::RACTOR_CONFIG)
