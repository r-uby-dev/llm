# frozen_string_literal: true

require "net/http"

class LLM::Transport
  ##
  # The {LLM::Transport::HTTP LLM::Transport::HTTP} transport is the
  # built-in adapter for Ruby's `Net::HTTP`. It manages
  # transient HTTP connections, tracks active requests by owner, and
  # interrupts in-flight requests when needed.
  #
  # @api private
  class HTTP < self
    include NetHTTPAdapter

    INTERRUPT_ERRORS = [::IOError, ::EOFError, Errno::EBADF].freeze
    ActiveRequest = Struct.new(:client, keyword_init: true)

    ##
    # @param [String] host
    # @param [Integer] port
    # @param [Integer] timeout
    # @param [Boolean] ssl
    # @return [LLM::Transport::HTTP]
    def initialize(host:, port:, timeout:, ssl:)
      @host = host
      @port = port
      @timeout = timeout
      @ssl = ssl
      @base_uri = URI("#{ssl ? "https" : "http"}://#{host}:#{port}/")
      @monitor = Monitor.new
    end

    ##
    # Returns the current request owner.
    # @return [Object]
    def request_owner
      return Fiber.current unless defined?(::Async)
      Async::Task.current? ? Async::Task.current : Fiber.current
    end

    ##
    # @return [Array<Class<Exception>>]
    def interrupt_errors
      [*INTERRUPT_ERRORS, *optional_interrupt_errors]
    end

    ##
    # Interrupt an active request, if any.
    # @param [Fiber] owner
    # @return [nil]
    def interrupt!(owner)
      req = request_for(owner) or return
      lock { (@interrupts ||= {})[owner] = true }
      close_socket(req.client)
      req.client.finish if req.client.active?
      owner.stop if owner.respond_to?(:stop)
    rescue *interrupt_errors
      nil
    end

    ##
    # Returns whether an execution owner was interrupted.
    # @param [Fiber] owner
    # @return [Boolean, nil]
    def interrupted?(owner)
      lock { @interrupts&.delete(owner) }
    end

    ##
    # Performs a request on the current HTTP transport.
    # Accepts both `Net::HTTPRequest` and {LLM::Transport::Request}.
    #
    # @param [Net::HTTPRequest, LLM::Transport::Request] request
    # @param [Fiber] owner
    # @param [LLM::Object, nil] stream
    # @yieldparam [LLM::Transport::Response] response
    # @return [Object]
    def request(request, owner:, stream: nil, &b)
      http_req = resolve_request(request)
      client = client()
      set_request(ActiveRequest.new(client:), owner)
      perform_request(client, http_req, stream, &b)
    ensure
      clear_request(owner)
    end

    ##
    # @return [String]
    def inspect
      "#<#{LLM::Utils.object_id(self)}>"
    end

    private

    attr_reader :host, :port, :timeout, :ssl, :base_uri

    def client
      client = Net::HTTP.new(host, port)
      client.read_timeout = timeout
      client.use_ssl = ssl
      client
    end

    def close_socket(http)
      socket = http&.instance_variable_get(:@socket) or return
      socket = socket.io if socket.respond_to?(:io)
      socket.close
    rescue *interrupt_errors
      nil
    end

    def request_for(owner)
      lock do
        @requests ||= {}
        @requests[owner]
      end
    end

    def set_request(req, owner)
      lock do
        @requests ||= {}
        @requests[owner] = req
      end
    end

    def clear_request(owner)
      lock { @requests&.delete(owner) }
    end

    def lock(&)
      @monitor.synchronize(&)
    end

    def optional_interrupt_errors
      defined?(::Async::Stop) ? [Async::Stop] : []
    end
  end
end
