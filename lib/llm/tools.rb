# frozen_string_literal: true

require_relative "tools/git"
require_relative "tools/unix"
Dir[File.join(__dir__, "tools", "*.rb")].each { require(it) }
