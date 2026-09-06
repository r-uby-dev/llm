# frozen_string_literal: true

class LLM::Console
  ##
  # This class maintains conversation state that includes
  # the conversation itself, and metadata associated with
  # the conversation.
  #
  # Internally it maintains an array where each element
  # represents a row, and each element in a row is a Hash
  # that describes a piece of text and any styles that might
  # be applied to it by the UI thread.
  #
  # It also maintains a cursor that tracks the active row
  # by its index number. The streaming path reuses a single
  # row by overwriting its contents repeatedly.
  class Buffer
    ##
    # @param [LLM::Console] console
    #  An instance of {LLM::Console LLM::Console}.
    # @return [LLM::Console::Buffer]
    def initialize(repl)
      @repl   = repl
      @window = repl.window
      @rows = [[], []]
      @cursor = nil
      @snapshot = nil
      @offset = 0
    end

    ##
    # @param [String, Array] chars
    # @param [Object] attrs
    # @param [Symbol] method
    # @return [void]
    def write(chars, attrs = nil, method: :append)
      case chars
      when Array then chunks = chars
      else chunks = [Node.new(chars.to_s, attrs)]
      end
      self.method(method).call(chunks)
    end

    ##
    # @param [String] user
    # @param [String, Array] content
    # @param [Symbol] method
    # @return [void]
    def write_message(user, content, method: :append)
      chunks = [Node.new("#{user}:\n", Curses::A_BOLD | Color.blue)]
      case content
      when Array then chunks.concat(content)
      else chunks.push(Node.new(content))
      end
      chunks.push(Node.new("\n\n"))
      write(chunks, method:)
    end

    ##
    # Open the buffer.
    # @return [void]
    def open
      @cursor = @rows.size - 1
      @snapshot = @rows.map(&:dup)
    end

    ##
    # Close the buffer.
    # @return [void]
    def close
      @cursor = nil
      @snapshot = nil
    end

    ##
    # @return [void]
    def scroll_up(height)
      max = [rows.size - height, 0].max
      @offset = [@offset + 1, max].min
    end

    ##
    # @return [void]
    def scroll_down
      @offset = [@offset - 1, 0].max
    end

    ##
    # @return [void]
    def scroll_to_bottom
      @offset = 0
    end

    ##
    # The width of the centered content area -
    # with 20% on each side. The rest makes up
    # the width of the buffer.
    # @return [Integer]
    def width
      (Curses.cols * 0.6).floor
    end

    ##
    # @param [Integer] height
    # @return [Array<String>]
    def visible(height)
      all = rows
      last = all.size - 1 - @offset
      first = [last - height + 1, 0].max
      all[first..last] || []
    end

    private

    ##
    # @api private
    attr_reader :repl, :window

    ##
    # Appends a new row
    # @param [Array<Node>] chunks
    #  One or more chunks.
    # @return [void]
    def append(chunks)
      chunks.each { wrap(_1, @rows) }
    end

    ##
    # Replaces the content of the active row
    # @param [Array<Node>] chunks
    #  One or more chunks.
    # @return [void]
    def replace(chunks)
      @rows = @snapshot.map(&:dup)
      chunks.each { wrap(_1, @rows) }
    end

    ##
    # Given a chunk this method wraps text to the buffer's
    # width. The text is split into words; a word that does
    # not fit on the current row moves to the next. Only a
    # single word longer than the whole width is hard-broken,
    # so text is never clipped by the window.
    def wrap(chunk, rows)
      attrs = chunk[:attrs]
      chunk[:text].to_s.scan(/\n|[^\s]+|\s+/) do |token|
        if token == "\n"
          rows << []
        elsif token.match?(/\s/)
          if sum(rows.last) + Node.width(token) <= width
            rows.last << Node.new(token, attrs)
          end
        elsif sum(rows.last) + Node.width(token) > width
          if sum(rows.last) == 0
            ##
            # A single word wider than the row: break it
            # every width columns.
            slices(token, width).each do |piece|
              rows.last << Node.new(piece, attrs)
              if sum(rows.last) >= width
                rows << []
              end
            end
          else
            rows << []
            rows.last << Node.new(token, attrs)
          end
        else
          rows.last << Node.new(token, attrs)
        end
      end
    end

    ##
    # @api private
    def rows
      @rows.dup.tap do |rows|
        ##
        # Discard empty rows that would otherwise
        # be rendered as newlines by the UI thread.
        # It's not the most elegant way to deal with
        # this and we probably shouldn't allow it to
        # happen in the first place.
        while rows.size > 1 and rows.last.empty?
          rows.pop
        end
      end
    end

    ##
    # @api private
    def sum(row)
      row.sum { _1.size }
    end

    ##
    # Splits a single word into pieces that each fit within the
    # buffer's width, measured in display columns.
    # @api private
    def slices(token, width)
      pieces = []
      remaining = token
      until remaining.empty?
        piece = Node.slice(remaining, width)
        pieces << piece
        remaining = remaining[piece.length..] || +""
      end
      pieces
    end
  end
end
