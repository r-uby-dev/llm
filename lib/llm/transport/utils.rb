# frozen_string_literal: true

class LLM::Transport
  ##
  # Shared utility methods for HTTP-backed transports.
  #
  # These methods resolve the transport options accepted by providers,
  # MCP HTTP clients, and A2A HTTP clients into concrete
  # {LLM::Transport} instances.
  #
  # @api private
  module Utils
    extend self

    ##
    # The transports a symbol can name.
    #
    # A name outside this list is refused rather than handed to
    # `LLM::Transport.public_send`, so a transport that was removed
    # (`:curb`) reads like one that never existed, and neither reads
    # as a `NoMethodError` from somewhere else in the runtime.
    # @return [Array<Symbol>]
    NAMES = %i[net_http net_http_persistent].freeze

    ##
    # Resolves a transport configuration into a transport instance.
    #
    # Nil values use the default Net::HTTP transport, or the persistent
    # Net::HTTP transport when `persistent` is true. Transport subclasses
    # are instantiated with the endpoint settings, symbols are resolved
    # through {LLM::Transport} shortcut methods, and transport instances
    # are returned as-is.
    #
    # @param [String] host
    # @param [Integer] port
    # @param [Integer, nil] timeout
    # @param [Integer] connect_timeout
    # @param [Boolean] ssl
    # @param [Boolean] persistent
    # @param [LLM::Transport, Class, Symbol, nil] transport
    # @raise [ArgumentError]
    #  When a symbol does not name a transport that exists
    # @return [LLM::Transport]
    def resolve_transport(host:, port:, timeout:, ssl:, persistent:, transport:, connect_timeout: 5)
      if transport.nil?
        default_transport(host:, port:, timeout:, connect_timeout:, ssl:, persistent:)
      elsif Class === transport && transport <= LLM::Transport
        transport.new(host:, port:, timeout:, connect_timeout:, ssl:)
      elsif Symbol === transport
        transport_class(transport).new(host:, port:, timeout:, connect_timeout:, ssl:)
      else
        transport
      end
    end

    private

    ##
    # Resolves a transport name to the class that implements it.
    # @param [Symbol] name
    # @return [Class]
    # @raise [ArgumentError]
    #  When the name is not among {NAMES}
    def transport_class(name)
      unless NAMES.include?(name)
        raise ArgumentError, "unknown transport: #{name.inspect} " \
                             "(supported: #{NAMES.map(&:inspect).join(", ")})"
      end
      LLM::Transport.public_send(name)
    end

    ##
    # Builds the default Net::HTTP transport for an endpoint.
    #
    # @param [String] host
    # @param [Integer] port
    # @param [Integer, nil] timeout
    # @param [Integer] connect_timeout
    # @param [Boolean] ssl
    # @param [Boolean] persistent
    # @return [LLM::Transport]
    def default_transport(host:, port:, timeout:, connect_timeout:, ssl:, persistent:)
      target = persistent ? LLM::Transport::PersistentHTTP : LLM::Transport::HTTP
      target.new(host:, port:, timeout:, connect_timeout:, ssl:)
    end
  end
end
