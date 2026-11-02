# frozen_string_literal: true

module LLM
  ##
  # @api private
  module Rescue
    ##
    # @api private
    ERRORS = [StandardError, ScriptError]
    private_constant :ERRORS

    ##
    # @param [StandardError] ex
    # @return [void]
    def crash(ex:)
      $stderr.puts "Oh no!",
                   "#{self.class} has crashed",
                   "",
                   "[  error     ] #{ex.class}",
                   "[  message   ] #{ex.message}",
                   "[  backtrace ] ",
                   "#{(ex.backtrace || []).take(10).join("\n")}",
                   ""
    end
  end
end
