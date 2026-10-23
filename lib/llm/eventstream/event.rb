# frozen_string_literal: true

module LLM::EventStream
  ##
  # @private
  class Event
    UNSET = ::Object.new.freeze

    def self.parse(chunk)
      newline = chunk.end_with?("\n") ? chunk.bytesize - 1 : chunk.bytesize
      separator = chunk.index(":")
      return [nil, nil] unless separator
      field = chunk.byteslice(0, separator)
      value_start = separator + (chunk.getbyte(separator + 1) == 32 ? 2 : 1)
      value = value_start < newline ? chunk.byteslice(value_start, newline - value_start) : nil
      [field, value]
    end

    ##
    # Returns the field name
    # @return [Symbol]
    attr_reader :field

    ##
    # Returns the field value
    # @return [String]
    attr_reader :value

    ##
    # Returns the full chunk
    # @return [String]
    attr_reader :chunk

    ##
    # @param [String] chunk
    # @return [LLM::EventStream::Event]
    def initialize(chunk, field: UNSET, value: UNSET)
      @field, @value = self.class.parse(chunk) if field.equal?(UNSET) || value.equal?(UNSET)
      @field = field unless field.equal?(UNSET)
      @value = value unless value.equal?(UNSET)
      @chunk = chunk
    end

    ##
    # Returns true when the event represents an "id" chunk
    # @return [Boolean]
    def id?
      @field == "id"
    end

    ##
    # Returns true when the event represents a "data" chunk
    # @return [Boolean]
    def data?
      @field == "data"
    end

    ##
    # Returns true when the event represents an "event" chunk
    # @return [Boolean]
    def event?
      @field == "event"
    end

    ##
    # Returns true when the event represents a "retry" chunk
    # @return [Boolean]
    def retry?
      @field == "retry"
    end

    ##
    # Returns true when a chunk represents the end of the stream
    # @return [Boolean]
    def end?
      @value == "[DONE]"
    end
  end
end
