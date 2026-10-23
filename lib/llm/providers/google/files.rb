# frozen_string_literal: true

class LLM::Google
  ##
  # The {LLM::Google::Files LLM::Google::Files} class provides a files
  # object for interacting with [Gemini's Files API](https://ai.google.dev/gemini-api/docs/files).
  # The files API allows a client to reference media files in prompts
  # where they can be referenced by their URL.
  #
  # The files API is intended to preserve bandwidth and latency,
  # especially for large files but it can be helpful for smaller files
  # as well because it does not require the client to include a file
  # in the prompt over and over again (which could be the case in a
  # multi-turn conversation).
  #
  # @example example #1
  #   #!/usr/bin/env ruby
  #   require "llm"
  #
  #   llm = LLM.google(key: ENV["KEY"])
  #   ctx = LLM::Context.new(llm)
  #   file = llm.files.create(file: "/audio/haiku.mp3")
  #   ctx.talk ["Tell me about this file", file]
  #   ctx.messages.select(&:assistant?).each { print "[#{_1.role}]", _1.content, "\n" }
  class Files
    ##
    # Returns a new Files object
    # @param llm [LLM::Provider]
    # @return [LLM::Google::Files]
    def initialize(llm)
      @llm = llm
    end

    ##
    # List all files
    # @example
    #   llm = LLM.google(key: ENV["KEY"])
    #   res = llm.files.all
    #   res.each do |file|
    #     print "name: ", file.name, "\n"
    #   end
    # @see https://ai.google.dev/gemini-api/docs/files Gemini docs
    # @param [Hash] params Other parameters (see Gemini docs)
    # @raise (see LLM::Provider#request)
    # @return [LLM::Response]
    def all(**params)
      query = URI.encode_www_form(params.merge!(key: key))
      req = LLM::Transport::Request.get("/v1beta/files?#{query}", headers)
      res, span, tracer, request_id = execute(request: req, operation: "request")
      res = ResponseAdapter.adapt(res, type: :files)
      tracer.on_request_finish(operation: "request", res:, span:, request_id:)
      res
    end

    ##
    # Create a file
    # @example
    #   llm = LLM.google(key: ENV["KEY"])
    #   res = llm.files.create(file: "/audio/haiku.mp3")
    # @see https://ai.google.dev/gemini-api/docs/files Gemini docs
    # @param [String, LLM::File] file The file
    # @param [Hash] params Other parameters (see Gemini docs)
    # @raise (see LLM::Provider#request)
    # @return [LLM::Response]
    def create(file:, **params)
      file = LLM.File(file)
      req = LLM::Transport::Request.post(request_upload_url(file:), {})
      req["content-length"] = file.bytesize
      req["X-Goog-Upload-Offset"] = 0
      req["X-Goog-Upload-Command"] = "upload, finalize"
      file.with_io do |io|
        transport.set_body_stream(req, io)
        res, span, tracer, request_id = execute(request: req, operation: "request")
        res = ResponseAdapter.adapt(res, type: :file)
        tracer.on_request_finish(operation: "request", res:, span:, request_id:)
        res
      end
    end

    ##
    # Get a file
    # @example
    #   llm = LLM.google(key: ENV["KEY"])
    #   res = llm.files.get(file: "files/1234567890")
    #   print "name: ", res.name, "\n"
    # @see https://ai.google.dev/gemini-api/docs/files Gemini docs
    # @param [#name, String] file The file to get
    # @param [Hash] params Other parameters (see Gemini docs)
    # @raise (see LLM::Provider#request)
    # @return [LLM::Response]
    def get(file:, **params)
      file_id = file.respond_to?(:name) ? file.name : file.to_s
      query = URI.encode_www_form(params.merge!(key: key))
      req = LLM::Transport::Request.get("/v1beta/#{file_id}?#{query}", headers)
      res, span, tracer, request_id = execute(request: req, operation: "request")
      res = ResponseAdapter.adapt(res, type: :file)
      tracer.on_request_finish(operation: "request", res:, span:, request_id:)
      res
    end

    ##
    # Delete a file
    # @example
    #   llm = LLM.google(key: ENV["KEY"])
    #   res = llm.files.delete(file: "files/1234567890")
    # @see https://ai.google.dev/gemini-api/docs/files Gemini docs
    # @param [#name, String] file The file to delete
    # @param [Hash] params Other parameters (see Gemini docs)
    # @raise (see LLM::Provider#request)
    # @return [LLM::Response]
    def delete(file:, **params)
      file_id = file.respond_to?(:name) ? file.name : file.to_s
      query = URI.encode_www_form(params.merge!(key: key))
      req = LLM::Transport::Request.delete("/v1beta/#{file_id}?#{query}", headers)
      res, span, tracer, request_id = execute(request: req, operation: "request")
      res = LLM::Response.new(res)
      tracer.on_request_finish(operation: "request", res:, span:, request_id:)
      res
    end

    ##
    # @raise [NotImplementedError]
    #  This method is not implemented by Gemini
    def download
      raise NotImplementedError
    end

    private

    def request_upload_url(file:)
      req = LLM::Transport::Request.post("/upload/v1beta/files?key=#{key}", headers)
      req["X-Goog-Upload-Protocol"] = "resumable"
      req["X-Goog-Upload-Command"] = "start"
      req["X-Goog-Upload-Header-Content-Length"] = file.bytesize
      req["X-Goog-Upload-Header-Content-Type"] = file.mime_type
      req.body = LLM.json.dump({file: {display_name: File.basename(file.path)}})
      res, span, tracer, request_id = execute(request: req, operation: "request")
      trace_res = LLM::Response.new(res)
      tracer.on_request_finish(operation: "request", res: trace_res, span:, request_id:)
      res["x-goog-upload-url"]
    end

    def key
      @llm.instance_variable_get(:@key)
    end

    [:headers, :execute, :transport].each do |m|
      define_method(m) { |*args, **kwargs, &b| @llm.send(m, *args, **kwargs, &b) }
    end
  end
end
