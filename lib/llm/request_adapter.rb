# frozen_string_literal: true

module LLM
  ##
  # Shared by every provider's request adapter.
  # @api private
  module RequestAdapter
    require_relative "request_adapter/role"
  end
end
