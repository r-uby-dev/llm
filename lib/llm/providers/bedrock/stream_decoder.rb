# frozen_string_literal: true

class LLM::Bedrock
  ##
  # Decodes AWS Event Stream binary frames.
  #
  # Bedrock Converse Stream uses the AWS Event Stream protocol,
  # a binary framing format (not SSE). Each message has:
  #   - total length (4 bytes, big-endian)
  #   - headers length (4 bytes, big-endian)
  #   - prelude CRC (4 bytes)
  #   - headers (variable)
  #   - payload (variable, usually JSON)
  #   - message CRC (4 bytes)
  #
  # Implements #<< to match the interface expected by llm.rb's
  # streaming transport, so it can replace the SSE-based
  # StreamDecoder when streaming from Bedrock.
  #
  # @api private
  class StreamDecoder
    ##
    # @return [LLM::Bedrock::StreamParser]
    attr_reader :parser

    ##
    # @param [LLM::Bedrock::StreamParser] parser
    def initialize(parser)
      @buffer = +"".b
      @parser = parser
    end

    ##
    # Feeds a raw binary chunk into the decoder.
    # Accumulates data until complete frames are available,
    # then decodes them and passes the JSON payload to the parser.
    #
    # @param [String] chunk Raw binary data
    # @return [void]
    def <<(chunk)
      @buffer << chunk
      decode_frames
    end

    ##
    # @return [Hash] The fully constructed response body
    def body
      parser.body
    end

    ##
    # @return [void]
    def free
      @buffer.clear
      parser.free if parser.respond_to?(:free)
    end

    private

    def decode_frames
      loop do
        break if @buffer.bytesize < 12
        total_length = @buffer[0, 4].unpack1("N")
        break if @buffer.bytesize < total_length
        # headers_length = @buffer[4, 4].unpack1("N")
        # prelude_crc = @buffer[8, 4].unpack1("N")
        headers = decode_headers
        payload_start = 12 + headers[:length]
        payload_length = total_length - payload_start - 4
        payload = @buffer[payload_start, payload_length] if payload_length > 0
        # message_crc from last 4 bytes, not needed for our purposes
        json = payload ? LLM.json.load(payload) : {}
        parser.parse!(json, event_type: headers[:event_type]) if json.is_a?(Hash)
        @buffer = @buffer[total_length..] || +"".b
      end
    end

    def decode_headers
      headers_length = @buffer[4, 4].unpack1("N")
      offset = 12
      end_offset = offset + headers_length
      result = {event_type: nil, length: headers_length}
      while offset < end_offset
        name_len = @buffer.getbyte(offset)
        offset += 1
        break if offset + name_len > end_offset
        name = @buffer[offset, name_len]
        offset += name_len
        break if offset >= end_offset
        value_type = @buffer.getbyte(offset)
        offset += 1
        value = case value_type
        when 7 # string
          str_len = @buffer[offset, 2].unpack1("n")
          offset += 2
          str = @buffer[offset, str_len]
          offset += str_len
          str
        when 8 # binary
          bin_len = @buffer[offset, 2].unpack1("n")
          offset += 2
          bin = @buffer[offset, bin_len]
          offset += bin_len
          bin
        when 9 # boolean true
          true
        when 1 # boolean false
          false
        when 2 # byte
          val = @buffer.getbyte(offset)
          offset += 1
          val
        when 3 # int16
          val = @buffer[offset, 2].unpack1("s>")
          offset += 2
          val
        when 4 # int32
          val = @buffer[offset, 4].unpack1("l>")
          offset += 4
          val
        when 6 # byte array (as raw string)
          bin_len = @buffer[offset, 2].unpack1("n")
          offset += 2
          bin = @buffer[offset, bin_len]
          offset += bin_len
          bin
        else
          # Unknown type, skip to end of headers
          offset = end_offset
          nil
        end
        result[:event_type] = value if name == ":event-type"
        result[name] = value if name
      end
      result
    end
  end
end
