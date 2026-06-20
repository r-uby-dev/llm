# frozen_string_literal: true

module LLM
  ##
  # The {LLM::Pipe LLM::Pipe} class wraps a pair of IO objects created by
  # `IO.pipe`. It is used by llm.rb internals to manage process and stream
  # communication through one small interface.
  class Pipe
    ##
    # @return [IO]
    #  Returns the reader
    attr_reader :r

    ##
    # @return [IO]
    #  Returns the writer
    attr_reader :w

    ##
    # Returns a new pipe.
    # @param [Boolean] binmode
    #  Whether both ends of the pipe should be switched to binary mode
    # @return [LLM::Pipe]
    def initialize(binmode: false)
      @r, @w = IO.pipe
      [@r, @w].each(&:binmode) if binmode
    end

    ##
    # Reads from the reader end without blocking.
    # @raise [IO::EAGAINWaitReadable]
    #  When no data is available to read
    # @return [String]
    def read_nonblock(...)
      @r.read_nonblock(...)
    end

    ##
    # Writes to the writer.
    # @return [Integer]
    def write(...)
      @w.write(...)
    end

    ##
    # Flushes the writer.
    # @return [void]
    def flush
      @w.flush
    end

    ##
    # Returns true when both ends are closed.
    # @return [Boolean]
    def closed?
      [@r, @w].all?(&:closed?)
    end

    ##
    # Closes both ends of the pipe.
    # @return [void]
    def close
      [@r, @w].each(&:close)
    rescue IOError
    end

    ##
    # Closes the reader.
    # @return [void]
    def close_reader
      @r.close
    rescue IOError
    end

    ##
    # Closes the writer.
    # @return [void]
    def close_writer
      @w.close
    rescue IOError
    end
  end
end
