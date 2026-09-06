# frozen_string_literal: true

class LLM::Console
  ##
  # The {LLM::Console::Window LLM::Console::Window} class draws the
  # curses screen for the REPL.
  # @api private
  class Window
    ##
    # Rows reserved for the top chrome (the blue model/cwd row).
    # @api private
    TOP_ROWS = 1

    ##
    # @return [LLM::Console::Status]
    attr_reader :status

    ##
    # @return [LLM::Console::Buffer]
    attr_reader :buffer

    ##
    # @return [LLM::Console::Input]
    attr_reader :input

    ##
    # @param [LLM::Console] console
    #  A read-eval-print loop.
    # @return [LLM::Console::Window]
    def initialize(repl)
      @repl   = repl
      @status = repl.status
      @buffer = repl.buffer
      @input  = repl.input
    end

    ##
    # @yield
    # @return [void]
    def open
      Curses.init_screen
      Color.enable
      Curses.cbreak
      Curses.noecho
      Curses.stdscr.keypad(true)
      Curses.stdscr.nodelay = true
      hide_cursor
      yield
    ensure
      show_cursor
      Curses.close_screen
    end

    ##
    # @return [void]
    def redraw
      draw_meta(offset: Curses.lines)
      draw_status(offset: input.height + 1)
      draw_divider(offset: 5)
      draw_buffer(offset: TOP_ROWS)
      draw_input
      Curses.refresh
    end

    ##
    # @return [Integer]
    def rows
      [Curses.lines - (input.height + 4), 1].max
    end

    ##
    # @return [Integer]
    def columns
      Curses.cols
    end

    ##
    # Redraws the window after it has been resized.
    # @return [void]
    def resize
      Curses.clear
      redraw
    end

    ##
    # @return [Object]
    def getch
      Curses.getch
    end

    ##
    # Drains all available characters from the terminal input
    # buffer without blocking.  Used in place of `Curses.getstr`
    # when the paste flag is set, so that a huge multi-line
    # paste is consumed in a single shot instead of being
    # processed character-by-character.
    # @return [String]
    def read_paste
      chars = +""
      loop do
        ch = Curses.getch
        break unless ch and ch != -1
        chars << ch
      end
      input.paste = false
      chars
    end

    ##
    # @return [void]
    def scroll_up
      buffer.scroll_up(rows)
    end

    ##
    # @return [void]
    def scroll_down
      buffer.scroll_down
    end

    ##
    # @return [void]
    def scroll_to_bottom
      buffer.scroll_to_bottom
    end

    private

    ##
    # Draws the window's primary content
    # @return [void]
    def draw_buffer(offset:)
      rows = buffer.visible(self.rows)
      rows.each.with_index(TOP_ROWS) do |row, index|
        Curses.setpos(index, 0)
        Curses.clrtoeol
        Curses.setpos(index, gutter)
        width = 0
        row.each do |chunk|
          remaining = buffer.width - width
          break if remaining <= 0
          text, attrs = chunk.text.to_s, chunk.attrs
          clipped = Node.slice(text, remaining)
          Curses.attron(attrs) if attrs
          Curses.addstr(clipped)
          Curses.attroff(attrs) if attrs
          width += Node.width(clipped)
        end
      end
      last_drawn = offset + rows.size
      (last_drawn...(Curses.lines - 5)).each do |line|
        Curses.setpos(line, 0)
        Curses.clrtoeol
      end
    end

    ##
    # Draws the status line
    # @return [void]
    def draw_status(offset:)
      y = Curses.lines - offset
      Curses.setpos(y, 0)
      Curses.clrtoeol
      status.nodes.each { addnode(_1) }
      context = status.context_bar
      Curses.setpos(y, [(columns - Node.width(context)) / 2, 0].max)
      Curses.addstr(context)
      cost = status.cost.to_s
      Curses.setpos(y, [columns - Node.width(cost), 0].max)
      Curses.addstr(cost)
    end

    ##
    # Draws the top chrome row (model left, cwd right) at the very top
    # of the screen, with a blue background.
    # @param [Integer] offset
    # @return [void]
    def draw_meta(offset:)
      y = Curses.lines - offset
      fill_row(y) do
        addnode(status.cwd, Node.slice(status.cwd.text, columns))
        Curses.setpos(y, [columns - status.model.size, 0].max)
        addnode(status.model, Node.slice(status.model.text, columns))
      end
    end

    ##
    # Fills an entire row with the status-bar background color, then
    # draws the given content on top (which inherits the blue
    # background), and resets the background afterwards.
    # @param [Integer] y
    # @yield Content to draw on the row
    # @return [void]
    def fill_row(y, &)
      Curses.setpos(y, 0)
      Curses.bkgdset(Color.statusbar)
      Curses.clrtoeol
      yield
      Curses.bkgdset(0)
    end

    ##
    # Draws a horiztonal line
    # @return [void]
    def draw_divider(offset:)
      Curses.setpos(Curses.lines - offset, 0)
      Curses.clrtoeol
      Curses.addstr("─" * Curses.cols)
    end

    ##
    # Draws the input area
    # @return [void]
    def draw_input
      rows = input.lines
      (0...input.height).each do |idx|
        Curses.setpos((Curses.lines - input.height) + idx, 0)
        Curses.clrtoeol
        Curses.addstr(rows[idx]) if idx < rows.length
      end
      line, col = input.cursor_pos
      Curses.setpos((Curses.lines - input.height) + line, col)
      show_cursor
    end

    ##
    # Hides the cursor.
    # @return [void]
    def hide_cursor
      Curses.curs_set(0)
    end

    ##
    # Shows the cursor.
    # @return [void]
    def show_cursor
      Curses.curs_set(1)
    end

    ##
    # 20% offset that occupies the left margin and
    # helps center {LLM::Console::Buffer LLM::Console::Buffer}.
    # @return [Integer]
    def gutter
      (columns * 0.2).floor
    end

    ##
    # Adds a {LLM::Console::Node} to the Curses window.
    # @param [LLM::Console::Node] node
    # @param [String] text
    # @return [void]
    def addnode(node, text = node.text)
      Curses.attron(node.attrs) if node.attrs
      Curses.addstr(text)
      Curses.attroff(node.attrs) if node.attrs
    end
  end
end
