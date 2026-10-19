# frozen_string_literal: true

module LLM
  ##
  # The JSONAdapter class defines the interface for JSON parsers
  # that can be used by the library when dealing with JSON. The
  # following parsers are supported:
  # * {LLM::JSONAdapter::JSON LLM::JSONAdapter::JSON} (default)
  # * {LLM::JSONAdapter::Oj LLM::JSONAdapter::Oj}
  #
  # @example Change parser
  #   LLM.json = LLM::JSONAdapter::Oj
  class JSONAdapter
    ##
    # @return [String]
    #  Returns a JSON string representation of the given object
    def self.dump(*) = raise NotImplementedError

    ##
    # @return [Object]
    #  Returns a Ruby object parsed from the given JSON string
    def self.load(*) = raise NotImplementedError

    ##
    # @return [Exception]
    #  Returns the error raised when parsing fails
    def self.parser_error = [StandardError]

    ##
    # JSON must be UTF-8 per spec, so a compliant adapter
    # scrubs the strings it serializes. Walks +obj+ and
    # encodes every string found into a valid UTF-8 string,
    # replacing any invalid bytes. Adapters should call this
    # from their +dump+ before handing the object to the
    # underlying library.
    # @param [Object] obj
    # @return [Object]
    #  The object with every string normalized to valid UTF-8
    def self.normalize(obj)
      case obj
      when String then normalize_string(obj)
      when Array then obj.map { normalize(_1) }
      when Hash then obj.map { [_1, normalize(_2)] }.to_h
      when LLM::Object then obj.map { [_1, normalize(_2)] }.to_h
      else obj
      end
    end
    private_class_method :normalize

    ##
    # Normalizes a single string as a valid UTF-8 string that is
    # compatible with the JSON spec. BINARY-encoded strings are
    # read as UTF-8 and scrubbed when invalid; every other encoding
    # is transcoded to UTF-8, replacing invalid or undefined bytes.
    # @param [String] str
    # @return [String]
    def self.normalize_string(str)
      if str.encoding == Encoding::BINARY
        str = (+str).force_encoding("UTF-8")
        str.valid_encoding? ? str : str.scrub
      else
        str.encode("UTF-8", invalid: :replace, undef: :replace)
      end
    end
    private_class_method :normalize_string
  end

  ##
  # The {LLM::JSONAdapter::JSON LLM::JSONAdapter::JSON} class
  # provides a JSON adapter backed by the standard library
  # JSON module.
  class JSONAdapter::JSON < JSONAdapter
    ##
    # @return (see JSONAdapter#dump)
    def self.dump(obj, state = nil, **options)
      require "json" unless defined?(::JSON)
      if ::JSON::State === state
        ::JSON.generate(normalize(obj), state)
      elsif state
        ::JSON.dump(normalize(obj), state, **options)
      else
        ::JSON.dump(normalize(obj), **options)
      end
    end

    ##
    # @return (see JSONAdapter#load)
    def self.load(string, ...)
      require "json" unless defined?(::JSON)
      ::JSON.parse(string, ...)
    end

    ##
    # @return (see JSONAdapter#parser_error)
    def self.parser_error
      require "json" unless defined?(::JSON)
      [::JSON::ParserError]
    end
  end

  ##
  # The {LLM::JSONAdapter::Oj LLM::JSONAdapter::Oj} class
  # provides a JSON adapter backed by the Oj gem.
  class JSONAdapter::Oj < JSONAdapter
    ##
    # @return (see JSONAdapter#dump)
    def self.dump(obj, options = {})
      require "oj" unless defined?(::Oj)
      ::Oj.dump(normalize(obj), options.merge(mode: :compat))
    end

    ##
    # @return (see JSONAdapter#load)
    def self.load(string, options = {})
      require "oj" unless defined?(::Oj)
      ::Oj.load(string, options.merge(mode: :compat, symbol_keys: false, symbolize_names: false))
    end

    ##
    # @return (see JSONAdapter#parser_error)
    def self.parser_error
      require "oj" unless defined?(::Oj)
      [::Oj::ParseError, ::EncodingError]
    end
  end
end
