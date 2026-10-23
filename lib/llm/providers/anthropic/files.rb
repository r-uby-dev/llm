# frozen_string_literal: true

class LLM::Anthropic
  ##
  # The {LLM::Anthropic::Files LLM::Anthropic::Files} class provides a files
  # object for interacting with [Anthropic's Files API](https://docs.anthropic.com/en/docs/build-with-claude/files).
  #
  # @example
  #   #!/usr/bin/env ruby
  #   require "llm"
  #
  #   llm = LLM.anthropic(key: ENV["KEY"])
  #   ctx = LLM::Context.new(llm)
  #   file = llm.files.create file: "/books/goodread.pdf"
  #   ctx.talk ["Tell me about this PDF", file]
  #   ctx.messages.select(&:assistant?).each { print "[#{_1.role}]", _1.content, "\n" }
  class Files
    ##
    # Returns a new Files object
    # @param llm [LLM::Provider]
    # @return [LLM::Anthropic::Files]
    def initialize(llm)
      @llm = llm
    end

    ##
    # List all files
    # @example
    #   llm = LLM.anthropic(key: ENV["KEY"])
    #   res = llm.files.all
    #   res.each do |file|
    #     print "id: ", file.id, "\n"
    #   end
    # @see https://docs.anthropic.com/en/docs/build-with-claude/files Anthropic docs
    # @param [Hash] params Other parameters (see Anthropic docs)
    # @raise (see LLM::Provider#request)
    # @return [LLM::Response]
    def all(**params)
      query = URI.encode_www_form(params)
      req = LLM::Transport::Request.get("/v1/files?#{query}", headers)
      res, span, tracer, request_id = execute(request: req, operation: "request")
      res = ResponseAdapter.adapt(res, type: :enumerable)
      tracer.on_request_finish(operation: "request", res:, span:, request_id:)
      res
    end

    ##
    # Create a file
    # @example
    #   llm = LLM.anthropic(key: ENV["KEY"])
    #   res = llm.files.create file: "/documents/haiku.txt"
    # @see https://docs.anthropic.com/en/docs/build-with-claude/files Anthropic docs
    # @param [File, LLM::File, String] file The file
    # @param [Hash] params Other parameters (see Anthropic docs)
    # @raise (see LLM::Provider#request)
    # @return [LLM::Response]
    def create(file:, **params)
      multi = LLM::Multipart.new(params.merge!(file: LLM.File(file)))
      req = LLM::Transport::Request.post("/v1/files", headers)
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
    #   llm = LLM.anthropic(key: ENV["KEY"])
    #   res = llm.files.get(file: "file-1234567890")
    #   print "id: ", res.id, "\n"
    # @see https://docs.anthropic.com/en/docs/build-with-claude/files Anthropic docs
    # @param [#id, #to_s] file The file ID
    # @param [Hash] params Other parameters - if any (see Anthropic docs)
    # @raise (see LLM::Provider#request)
    # @return [LLM::Response]
    def get(file:, **params)
      file_id = file.respond_to?(:id) ? file.id : file
      query = URI.encode_www_form(params)
      req = LLM::Transport::Request.get("/v1/files/#{file_id}?#{query}", headers)
      res, span, tracer, request_id = execute(request: req, operation: "request")
      res = ResponseAdapter.adapt(res, type: :file)
      tracer.on_request_finish(operation: "request", res:, span:, request_id:)
      res
    end

    ##
    # Retrieve file metadata
    # @example
    #   llm = LLM.anthropic(key: ENV["KEY"])
    #   res = llm.files.get_metadata(file: "file-1234567890")
    #   print "id: ", res.id, "\n"
    # @see https://docs.anthropic.com/en/docs/build-with-claude/files
    # @param [#id, #to_s] file The file ID
    # @param [Hash] params Other parameters - if any (see Anthropic docs)
    # @raise (see LLM::Provider#request)
    # @return [LLM::Response]
    def get_metadata(file:, **params)
      query = URI.encode_www_form(params)
      file_id = file.respond_to?(:id) ? file.id : file
      req = LLM::Transport::Request.get("/v1/files/#{file_id}?#{query}", headers)
      res, span, tracer, request_id = execute(request: req, operation: "request")
      res = ResponseAdapter.adapt(res, type: :file)
      tracer.on_request_finish(operation: "request", res:, span:, request_id:)
      res
    end
    alias_method :retrieve_metadata, :get_metadata

    ##
    # Delete a file
    # @example
    #   llm = LLM.anthropic(key: ENV["KEY"])
    #   res = llm.files.delete(file: "file-1234567890")
    #   print res.deleted, "\n"
    # @see https://docs.anthropic.com/en/docs/build-with-claude/files Anthropic docs
    # @param [#id, #to_s] file The file ID
    # @raise (see LLM::Provider#request)
    # @return [LLM::Response]
    def delete(file:)
      file_id = file.respond_to?(:id) ? file.id : file
      req = LLM::Transport::Request.delete("/v1/files/#{file_id}", headers)
      res, span, tracer, request_id = execute(request: req, operation: "request")
      res = LLM::Response.new(res)
      tracer.on_request_finish(operation: "request", res:, span:, request_id:)
      res
    end

    ##
    # Download the contents of a file
    # @note
    #   You can only download files that were created by the code
    #   execution tool. Files that you uploaded cannot be downloaded.
    # @example
    #   llm = LLM.anthropic(key: ENV["KEY"])
    #   res = llm.files.download(file: "file-1234567890")
    #   File.binwrite "program.c", res.file.read
    #   print res.file.read, "\n"
    # @see https://docs.anthropic.com/en/docs/build-with-claude/files Anthropic docs
    # @param [#id, #to_s] file The file ID
    # @param [Hash] params Other parameters (see Anthropic docs)
    # @raise (see LLM::Provider#request)
    # @return [LLM::Response]
    def download(file:, **params)
      query = URI.encode_www_form(params)
      file_id = file.respond_to?(:id) ? file.id : file
      req = LLM::Transport::Request.get("/v1/files/#{file_id}/content?#{query}", headers)
      io = StringIO.new("".b)
      res, span, tracer, request_id = execute(request: req, operation: "request") { |res| res.read_body { |chunk| io << chunk } }
      res = LLM::Response.new(res).tap { _1.define_singleton_method(:file) { io } }
      tracer.on_request_finish(operation: "request", res:, span:, request_id:)
      res
    end

    private

    def key
      @llm.instance_variable_get(:@key)
    end

    [:headers, :execute, :transport].each do |m|
      define_method(m) { |*args, **kwargs, &b| @llm.send(m, *args, **kwargs, &b) }
    end
  end
end
