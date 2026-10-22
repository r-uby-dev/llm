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
    # @raise [LLM::Error]
    #  When given an unknown transport
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
    # Resolves a transport name to the class
    # that implements it.
    # @param [Symbol] name
    # @raise [LLM::Error]
    #  When given an unknown transport
    # @return [Class]
    def transport_class(name)
      LLM::Transport.public_send(name)
    rescue NoMethodError
      raise LLM::Error, ":#{name} is not a recognized transport"
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
