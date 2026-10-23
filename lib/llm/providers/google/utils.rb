# frozen_string_literal: true

class LLM::Google
  module Utils
    ##
    # Returns a stable internal tool-call ID for a call.
    #
    # Gemini responses may omit a direct tool-call ID, but
    # llm.rb expects one for matching a pending call with
    # its return. The call's own ID is preferred, then the
    # candidate and part indexes, which are stable within
    # a response.
    #
    # @param part [Hash]
    #  A content part that holds a `functionCall`
    # @param cindex [Integer]
    #  The candidate index
    # @param pindex [Integer]
    #  The part index within the candidate
    # @return [String]
    def tool_id(part:, cindex:, pindex:)
      id = part.dig("functionCall", "id").to_s
      return "google_#{id}" unless id.empty?
      "google_call_#{cindex}_#{pindex}"
    end
  end
end
