# frozen_string_literal: true

class LLM::OpenAI
  ##
  # The {LLM::OpenAI::Files LLM::OpenAI::Files} class provides a files
  # object for interacting with [OpenAI's Files API](https://platform.openai.com/docs/api-reference/files/create).
  # The files API allows a client to upload files for use with OpenAI's models
  # and API endpoints. OpenAI supports multiple file formats, including text
  # files, CSV files, JSON files, and more.
  #
  # @example example #1
  #   #!/usr/bin/env ruby
  #   require "llm"
  #
  #   llm = LLM.openai(key: ENV["KEY"])
  #   ctx = LLM::Context.new(llm)
  #   file = llm.files.create file: "/books/goodread.pdf"
  #   ctx.talk ["Tell me about this PDF", file]
  #   ctx.messages.select(&:assistant?).each { print "[#{_1.role}]", _1.content, "\n" }
  class Files
    ##
    # Returns a new Files object
    # @param llm [LLM::Provider]
    # @return [LLM::OpenAI::Files]
    def initialize(llm)
      @llm = llm
    end

    ##
    # List all files
    # @example
    #   llm = LLM.openai(key: ENV["KEY"])
    #   res = llm.files.all
    #   res.each do |file|
    #     print "id: ", file.id, "\n"
    #   end
    # @see https://platform.openai.com/docs/api-reference/files/list OpenAI docs
    # @param [Hash] params Other parameters (see OpenAI docs)
    # @raise (see LLM::Provider#request)
    # @return [LLM::Response]
    def all(**params)
      query = URI.encode_www_form(params)
      req = LLM::Transport::Request.get(path("/files?#{query}"), headers)
      res, span, tracer, request_id = execute(request: req, operation: "request")
      res = ResponseAdapter.adapt(res, type: :enumerable)
      tracer.on_request_finish(operation: "request", res:, span:, request_id:)
      res
    end

    ##
    # Create a file
    # @example
    #   llm = LLM.openai(key: ENV["KEY"])
    #   res = llm.files.create file: "/documents/haiku.txt"
    # @see https://platform.openai.com/docs/api-reference/files/create OpenAI docs
    # @param [File, LLM::File, String] file The file
    # @param [String] purpose The purpose of the file (see OpenAI docs)
    # @param [Hash] params Other parameters (see OpenAI docs)
    # @raise (see LLM::Provider#request)
    # @return [LLM::Response]
    def create(file:, purpose: "assistants", **params)
      multi = LLM::Multipart.new(params.merge!(file: LLM.File(file), purpose:))
      req = LLM::Transport::Request.post(path("/files"), headers)
      req["content-type"] = multi.content_type
      transport.set_body_stream(req, multi.body)
      res, span, tracer, request_id = execute(request: req, operation: "request")
      res = ResponseAdapter.adapt(res, type: :file)
      tracer.on_request_finish(operation: "request", res:, span:, request_id:)
      res
    end

    ##
    # Get a file
    # @example
    #   llm = LLM.openai(key: ENV["KEY"])
    #   res = llm.files.get(file: "file-1234567890")
    #   print "id: ", res.id, "\n"
    # @see https://platform.openai.com/docs/api-reference/files/get OpenAI docs
    # @param [#id, #to_s] file The file ID
    # @param [Hash] params Other parameters (see OpenAI docs)
    # @raise (see LLM::Provider#request)
    # @return [LLM::Response]
    def get(file:, **params)
      file_id = file.respond_to?(:id) ? file.id : file
      query = URI.encode_www_form(params)
      req = LLM::Transport::Request.get(path("/files/#{file_id}?#{query}"), headers)
      res, span, tracer, request_id = execute(request: req, operation: "request")
      res = ResponseAdapter.adapt(res, type: :file)
      tracer.on_request_finish(operation: "request", res:, span:, request_id:)
      res
    end

    ##
    # Download the content of a file
    # @example
    #   llm = LLM.openai(key: ENV["KEY"])
    #   res = llm.files.download(file: "file-1234567890")
    #   File.binwrite "haiku1.txt", res.file.read
    #   print res.file.read, "\n"
    # @see https://platform.openai.com/docs/api-reference/files/content OpenAI docs
    # @param [#id, #to_s] file The file ID
    # @param [Hash] params Other parameters (see OpenAI docs)
    # @raise (see LLM::Provider#request)
    # @return [LLM::Response]
    def download(file:, **params)
      query = URI.encode_www_form(params)
      file_id = file.respond_to?(:id) ? file.id : file
      req = LLM::Transport::Request.get(path("/files/#{file_id}/content?#{query}"), headers)
      io = StringIO.new("".b)
      res, span, tracer, request_id = execute(request: req, operation: "request") { |res| res.read_body { |chunk| io << chunk } }
      res = LLM::Response.new(res).tap { _1.define_singleton_method(:file) { io } }
      tracer.on_request_finish(operation: "request", res:, span:, request_id:)
      res
    end

    ##
    # Delete a file
    # @example
    #   llm = LLM.openai(key: ENV["KEY"])
    #   res = llm.files.delete(file: "file-1234567890")
    #   print res.deleted, "\n"
    # @see https://platform.openai.com/docs/api-reference/files/delete OpenAI docs
    # @param [#id, #to_s] file The file ID
    # @raise (see LLM::Provider#request)
    # @return [LLM::Response]
    def delete(file:)
      file_id = file.respond_to?(:id) ? file.id : file
      req = LLM::Transport::Request.delete(path("/files/#{file_id}"), headers)
      res, span, tracer, request_id = execute(request: req, operation: "request")
      res = LLM::Response.new(res)
      tracer.on_request_finish(operation: "request", res:, span:, request_id:)
      res
    end

    private

    [:path, :headers, :execute, :transport].each do |m|
      define_method(m) { |*args, **kwargs, &b| @llm.send(m, *args, **kwargs, &b) }
    end
  end
end
