# frozen_string_literal: true

module RbConfig
  ##
  # Deep-dup via Ractor.new
  # Returns a deeply frozen RbConfig::CONFIG
  # @api private
  # @return [Hash]
  RACTOR_CONFIG = Ractor.new(RbConfig::CONFIG) { Ractor.make_shareable(it) }.value

  ##
  # Ractor-side Ruby method that can
  # be accessed across ractors. This
  # is used by the ruby.rb tool.
  # @return [String]
  def self.ruby
    File.join(
      RACTOR_CONFIG["bindir"],
      RACTOR_CONFIG["ruby_install_name"] + RACTOR_CONFIG["EXEEXT"]
    )
  end
end unless RbConfig.const_defined?(:RACTOR_CONFIG)
