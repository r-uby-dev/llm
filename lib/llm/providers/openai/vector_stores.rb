# frozen_string_literal: true

class LLM::OpenAI
  ##
  # The {LLM::OpenAI::VectorStores LLM::OpenAI::VectorStores} class provides
  # an interface for [OpenAI's vector stores API](https://platform.openai.com/docs/api-reference/vector_stores/create).
  #
  # @example
  #  llm = LLM.openai(key: ENV["OPENAI_SECRET"])
  #  files = %w(foo.pdf bar.pdf).map { llm.files.create(file: _1) }
  #  store = llm.vector_stores.create_and_poll(name: "PDF Store", file_ids: files.map(&:id))
  #  print "[-] store is ready", "\n"
  #  chunks = llm.vector_stores.search(vector: store, query: "What is Ruby?")
  #  chunks.each { |chunk| puts chunk }
  class VectorStores
    PollError = Class.new(LLM::Error)

    INTERVAL = 0.01
    private_constant :INTERVAL

    ##
    # @param [LLM::Provider] llm
    #  An OpenAI provider
    def initialize(llm)
      @llm = llm
    end

    ##
    # List all vector stores
    # @param [Hash] params Other parameters (see OpenAI docs)
    # @return [LLM::Response]
    def all(**params)
      query = URI.encode_www_form(params)
      req = LLM::Transport::Request.get(path("/vector_stores?#{query}"), headers)
      res, span, tracer, request_id = execute(request: req, operation: "request")
      res = ResponseAdapter.adapt(res, type: :enumerable)
      tracer.on_request_finish(operation: "request", res:, span:, request_id:)
      res
    end

    ##
    # Create a vector store
    # @param [String] name The name of the vector store
    # @param [Array<String>] file_ids The IDs of the files to include in the vector store
    # @param [Hash] params Other parameters (see OpenAI docs)
    # @raise (see LLM::Provider#request)
    # @return [LLM::Response]
    # @see https://platform.openai.com/docs/api-reference/vector_stores/create OpenAI docs
    def create(name:, file_ids: nil, **params)
      req = LLM::Transport::Request.post(path("/vector_stores"), headers)
      req.body = LLM.json.dump(params.merge({name:, file_ids:}).compact)
      res, span, tracer, request_id = execute(request: req, operation: "request")
      res = LLM::Response.new(res)
      tracer.on_request_finish(operation: "request", res:, span:, request_id:)
      res
    end

    ##
    # Create a vector store and poll until its status is "completed"
    # @param interval [Float] The interval between polling attempts (seconds)
    # @param (see LLM::OpenAI::VectorStores#create)
    # @return (see LLM::OpenAI::VectorStores#poll)
    def create_and_poll(interval: INTERVAL, **rest)
      poll(interval:, vector: create(**rest))
    end

    ##
    # Get a vector store
    # @param [String, #id] vector The ID of the vector store
    # @raise (see LLM::Provider#request)
    # @return [LLM::Response]
    # @see https://platform.openai.com/docs/api-reference/vector_stores/retrieve OpenAI docs
    def get(vector:)
      vector_id = vector.respond_to?(:id) ? vector.id : vector
      req = LLM::Transport::Request.get(path("/vector_stores/#{vector_id}"), headers)
      res, span, tracer, request_id = execute(request: req, operation: "request")
      res = LLM::Response.new(res)
      tracer.on_request_finish(operation: "request", res:, span:, request_id:)
      res
    end

    ##
    # Modify an existing vector store
    # @param [String, #id] vector The ID of the vector store
    # @param [String] name The new name of the vector store
    # @param [Hash] params Other parameters (see OpenAI docs)
    # @raise (see LLM::Provider#request)
    # @return [LLM::Response]
    # @see https://platform.openai.com/docs/api-reference/vector_stores/modify OpenAI docs
    def modify(vector:, name: nil, **params)
      vector_id = vector.respond_to?(:id) ? vector.id : vector
      req = LLM::Transport::Request.post(path("/vector_stores/#{vector_id}"), headers)
      req.body = LLM.json.dump(params.merge({name:}).compact)
      res, span, tracer, request_id = execute(request: req, operation: "request")
      res = LLM::Response.new(res)
      tracer.on_request_finish(operation: "request", res:, span:, request_id:)
      res
    end

    ##
    # Delete a vector store
    # @param [String, #id] vector The ID of the vector store
    # @raise (see LLM::Provider#request)
    # @return [LLM::Response]
    # @see https://platform.openai.com/docs/api-reference/vector_stores/delete OpenAI docs
    def delete(vector:)
      vector_id = vector.respond_to?(:id) ? vector.id : vector
      req = LLM::Transport::Request.delete(path("/vector_stores/#{vector_id}"), headers)
      res, span, tracer, request_id = execute(request: req, operation: "request")
      res = LLM::Response.new(res)
      tracer.on_request_finish(operation: "request", res:, span:, request_id:)
      res
    end

    ##
    # Search a vector store
    # @param [String, #id] vector The ID of the vector store
    # @param query [String] The query to search for
    # @param params [Hash] Other parameters (see OpenAI docs)
    # @raise (see LLM::Provider#request)
    # @return [LLM::Response]
    # @see https://platform.openai.com/docs/api-reference/vector_stores/search OpenAI docs
    def search(vector:, query:, **params)
      vector_id = vector.respond_to?(:id) ? vector.id : vector
      req = LLM::Transport::Request.post(path("/vector_stores/#{vector_id}/search"), headers)
      req.body = LLM.json.dump(params.merge({query:}).compact)
      res, span, tracer, request_id = execute(request: req, operation: "retrieval")
      res = ResponseAdapter.adapt(res, type: :enumerable)
      tracer.on_request_finish(operation: "retrieval", res:, span:, request_id:)
      res
    end

    ##
    # List all files in a vector store
    # @param [String, #id] vector The ID of the vector store
    # @param [Hash] params Other parameters (see OpenAI docs)
    # @raise (see LLM::Provider#request)
    # @return [LLM::Response]
    # @see https://platform.openai.com/docs/api-reference/vector_stores_files/listFiles OpenAI docs
    def all_files(vector:, **params)
      vector_id = vector.respond_to?(:id) ? vector.id : vector
      query = URI.encode_www_form(params)
      req = LLM::Transport::Request.get(path("/vector_stores/#{vector_id}/files?#{query}"), headers)
      res, span, tracer, request_id = execute(request: req, operation: "request")
      res = ResponseAdapter.adapt(res, type: :enumerable)
      tracer.on_request_finish(operation: "request", res:, span:, request_id:)
      res
    end

    ##
    # Add a file to a vector store
    # @param [String, #id] vector The ID of the vector store
    # @param [String, #id] file The ID of the file to add
    # @param [Hash] attributes Attributes to associate with the file (optional)
    # @param [Hash] params Other parameters (see OpenAI docs)
    # @raise (see LLM::Provider#request)
    # @return [LLM::Response]
    # @see https://platform.openai.com/docs/api-reference/vector_stores_files/createFile OpenAI docs
    def add_file(vector:, file:, attributes: nil, **params)
      vector_id = vector.respond_to?(:id) ? vector.id : vector
      file_id = file.respond_to?(:id) ? file.id : file
      req = LLM::Transport::Request.post(path("/vector_stores/#{vector_id}/files"), headers)
      req.body = LLM.json.dump(params.merge({file_id:, attributes:}).compact)
      res, span, tracer, request_id = execute(request: req, operation: "request")
      res = LLM::Response.new(res)
      tracer.on_request_finish(operation: "request", res:, span:, request_id:)
      res
    end
    alias_method :create_file, :add_file

    ##
    # Add a file to a vector store and poll until its status is "completed"
    # @param interval [Float] The interval between polling attempts (seconds)
    # @param (see LLM::OpenAI::VectorStores#add_file)
    # @return (see LLM::OpenAI::VectorStores#poll)
    def add_file_and_poll(vector:, file:, interval: INTERVAL, **rest)
      poll(vector:, interval:, file: add_file(vector:, file:, **rest))
    end
    alias_method :create_file_and_poll, :add_file_and_poll

    ##
    # Update a file in a vector store
    # @param [String, #id] vector The ID of the vector store
    # @param [String, #id] file The ID of the file to update
    # @param [Hash] attributes Attributes to associate with the file
    # @param [Hash] params Other parameters (see OpenAI docs)
    # @raise (see LLM::Provider#request)
    # @return [LLM::Response]
    # @see https://platform.openai.com/docs/api-reference/vector_stores_files/updateAttributes OpenAI docs
    def update_file(vector:, file:, attributes:, **params)
      vector_id = vector.respond_to?(:id) ? vector.id : vector
      file_id = file.respond_to?(:id) ? file.id : file
      req = LLM::Transport::Request.post(path("/vector_stores/#{vector_id}/files/#{file_id}"), headers)
      req.body = LLM.json.dump(params.merge({attributes:}).compact)
      res, span, tracer, request_id = execute(request: req, operation: "request")
      res = LLM::Response.new(res)
      tracer.on_request_finish(operation: "request", res:, span:, request_id:)
      res
    end

    ##
    # Get a file from a vector store
    # @param [String, #id] vector The ID of the vector store
    # @param [String, #id] file The ID of the file to retrieve
    # @raise (see LLM::Provider#request)
    # @return [LLM::Response]
    # @see https://platform.openai.com/docs/api-reference/vector_stores_files/getFile OpenAI docs
    def get_file(vector:, file:, **params)
      vector_id = vector.respond_to?(:id) ? vector.id : vector
      file_id = file.respond_to?(:id) ? file.id : file
      query = URI.encode_www_form(params)
      req = LLM::Transport::Request.get(path("/vector_stores/#{vector_id}/files/#{file_id}?#{query}"), headers)
      res, span, tracer, request_id = execute(request: req, operation: "request")
      res = LLM::Response.new(res)
      tracer.on_request_finish(operation: "request", res:, span:, request_id:)
      res
    end

    ##
    # Delete a file from a vector store
    # @param [String, #id] vector The ID of the vector store
    # @param [String, #id] file The ID of the file to delete
    # @raise (see LLM::Provider#request)
    # @return [LLM::Response]
    # @see https://platform.openai.com/docs/api-reference/vector_stores_files/deleteFile OpenAI docs
    def delete_file(vector:, file:)
      vector_id = vector.respond_to?(:id) ? vector.id : vector
      file_id = file.respond_to?(:id) ? file.id : file
      req = LLM::Transport::Request.delete(path("/vector_stores/#{vector_id}/files/#{file_id}"), headers)
      res, span, tracer, request_id = execute(request: req, operation: "request")
      res = LLM::Response.new(res)
      tracer.on_request_finish(operation: "request", res:, span:, request_id:)
      res
    end

    ##
    # Poll a vector store or file until its status is "completed"
    # @param [String, #id] vector The ID of the vector store
    # @param [String, #id] file The file to poll (optional)
    # @param [Integer] attempts The current number of attempts (default: 0)
    # @param [Integer] max The maximum number of iterations (default: 50)
    # @param [Float] interval The interval between polling attempts (seconds)
    # @raise [LLM::PollError] When the maximum number of iterations is reached
    # @return [LLM::Response]
    def poll(vector:, file: nil, attempts: 0, max: 50, interval: INTERVAL)
      target = file || vector
      if attempts == max
        raise LLM::PollError, "'#{target.id}' has status '#{target.status}' after #{max} attempts"
      elsif target.status == "expired"
        raise LLM::PollError, "#{target.id}' has expired"
      elsif target.status != "completed"
        file ? (file = get_file(vector:, file:)) : (vector = get(vector:))
        sleep(interval * (2**attempts)) unless interval.zero?
        poll(vector:, file:, attempts: attempts + 1, max:, interval:)
      else
        target
      end
    end

    private

    [:path, :headers, :execute].each do |m|
      define_method(m) { |*args, **kwargs, &b| @llm.send(m, *args, **kwargs, &b) }
    end
  end
end
