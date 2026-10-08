# frozen_string_literal: true

class LLM::DeepSeek
  ##
  # The {LLM::DeepSeek::Files LLM::DeepSeek::Files} class provides a files
  # object for interacting with [DeepSeek's Files API](https://api-docs.deepseek.com/guides/files_api).
  # The files API lets a client upload images and reference them later by
  # `file_id` - for example in chat requests to `deepseek-flash` - without
  # re-uploading them. DeepSeek supports the JPEG, PNG, GIF, and WebP formats,
  # and a single file may be at most 64 MiB.
  #
  # DeepSeek's Files API is OpenAI-compatible, with two differences from
  # OpenAI's: it is served from the root of the API host (not under `/v1`),
  # and the `purpose` of an upload must be `"user_data"`.
  #
  # @example example #1
  #   #!/usr/bin/env ruby
  #   require "llm"
  #
  #   llm = LLM.deepseek(key: ENV["KEY"])
  #   file = llm.files.create file: "/images/photo.jpg"
  #   print "id: ", file.id, "\n"
  class Files < LLM::OpenAI::Files
    ##
    # Create a file
    # @example
    #   llm = LLM.deepseek(key: ENV["KEY"])
    #   res = llm.files.create file: "/images/photo.jpg"
    # @see https://api-docs.deepseek.com/guides/files_api DeepSeek docs
    # @param [File, LLM::File, String] file The file
    # @param [String] purpose The purpose of the file (DeepSeek only supports "user_data")
    # @param [Hash] params Other parameters (see DeepSeek docs)
    # @raise (see LLM::Provider#request)
    # @return [LLM::Response]
    def create(file:, purpose: "user_data", **params)
      super
    end

    private

    ##
    # DeepSeek serves its Files API from the root of the API host,
    # while the rest of its OpenAI-compatible API lives under `/v1`
    # @see https://api-docs.deepseek.com/guides/files_api DeepSeek docs
    def path(suffix, **)
      @provider.send(:path, suffix, base_path: false)
    end
  end
end
