# frozen_string_literal: true

class LLM::Console
  ##
  # The {LLM::Console::Input LLM::Console::Input} class manages
  # the editable input line shown at the bottom of the REPL.
  # @api private
  class Input
    require_relative "input/row"
    require_relative "input/char"
    require_relative "input/cache"

    CTRL = {
      A: Curses::KEY_CTRL_A,
      E: Curses::KEY_CTRL_E,
      F: Curses::KEY_CTRL_F,
      K: Curses::KEY_CTRL_K,
      Y: Curses::KEY_CTRL_Y,
      D: Curses::KEY_CTRL_D,
      P: Curses::KEY_CTRL_P,
      N: Curses::KEY_CTRL_N
    }

    ##
    # This hash tracks how many times a given key
    # was pressed repeatedly without being
    # interrupted by another key. The previous key
    # is reset to 0 when a different key is pressed.
    REPEATS = {}
    REPEATS.default = 0

    UP         = Curses::Key::UP
    DOWN       = Curses::Key::DOWN
    LEFT       = Curses::Key::LEFT
    RIGHT      = Curses::Key::RIGHT
    PGUP       = Curses::KEY_PPAGE
    PGDOWN     = Curses::KEY_NPAGE
    KEY_RESIZE = Curses::KEY_RESIZE

    TAB       = 9
    ESC       = 27
    ENTER     = 10
    BACKSPACE = 127

    ##
    # Threshold in seconds. If characters arrive faster than
    # this, we assume the user is pasting multi-line text.
    # Human typing is ~150–300ms per key, so 50ms reliably
    # distinguishes a paste from manual typing.
    PASTE_THRESHOLD = 0.05

    ##
    # @param [Boolean] value
    # @return [void]
    attr_writer :paste

    ##
    # @param [LLM::Console] console
    # @return [LLM::Console::Input]
    def initialize(repl, options = {})
      @repl = repl
      @name = repl.name
      @agent = repl.agent
      @provider = @agent.llm.name
      @rows = [Row.new]
      @cursor = [0, 0]
      @scroll = 0
      @height = options.fetch(:height, 3)
      @last_char_at = nil
      @memory = @agent.messages.select(&:user?).map(&:content)
      @walker = Walker.new(@memory)
      @paste = false
    end

    ##
    # @return [String]
    #  The input buffer as an ordinary string.
    def buffer
      text
    end

    ##
    # @param [LLM::Console::Window] window
    # @param [Object] char
    # @return [Symbol, nil]
    def on_char(window, char, now)
      is_paste = lambda { @last_char_at and (now - @last_char_at) < PASTE_THRESHOLD }
      if char and @char != char
        REPEATS[@char] = 0
      end
      if PGUP == char
        (window.rows - 3).times { window.scroll_up }
        :pageup
      elsif PGDOWN == char
        (window.rows - 3).times { window.scroll_down }
        :pagedown
      elsif TAB == char
        autocomplete
        :tab
      elsif ESC == char
        @agent.cancel!
        ##
        # '@agent.cancel!' might do this for us already
        # but we can't rely on it alone. There are moments
        # in time where '@agent.cancel!' is essentially a
        # noop.
        @thread&.raise(LLM::Interrupt) if @thread&.alive?
      elsif CTRL[:P] == char
        set(text: @walker.prev.dup)
        :ctrl_p
      elsif CTRL[:N] == char
        set(text: @walker.next.dup)
        :ctrl_n
      elsif CTRL[:D] == char
        delete
        :ctrl_d
      elsif CTRL[:A] == char
        move_start
        :ctrl_a
      elsif CTRL[:E] == char
        move_end
        :ctrl_e
      elsif CTRL[:F] == char
        move_forward
        :ctrl_f
      elsif CTRL[:Y] == char
        restore
        :ctrl_y
      elsif CTRL[:K] == char
        kill
        :ctrl_k
      elsif char == LEFT
        move_left
        :left
      elsif char == RIGHT
        move_right
        :right
      elsif char == BACKSPACE
        backspace
        :backspace
      elsif char == ENTER
        if @paste = is_paste.()
          insert("\n")
          :char
        else
          @memory.push(text)
          @walker.cursor = @memory.size
          :submit
        end
      elsif char == KEY_RESIZE
        window.resize
        :resize
      elsif char == UP
        window.scroll_up
        :up
      elsif char == DOWN
        window.scroll_down
        :down
      elsif String === char
        ##
        # A paste arrives as a burst of fast characters. Flag it so the
        # next loop iteration drains the rest through read_paste in a
        # single shot, instead of inserting one character at a time and
        # redrawing after each. A string that is already the product of
        # read_paste (multi-character) is inserted as-is, one char at a
        # time, so every newline creates a row and every Char stays a
        # single character.
        @paste = true if char.length == 1 && is_paste.()
        char.each_char { |c| insert(c) }
        :char
      else
        nil
      end
    ensure
      if char
        REPEATS[char] += 1
        @last_char_at = now
        @char = char
      end
    end

    ##
    # @return [String]
    def to_s
      @rows
        .each_with_index
        .map { |row, i| (i.zero? ? prompt : "") + row.to_s }
        .join("\n")
    end

    ##
    # @return [Integer]
    def height
      @height
    end

    ##
    # Returns the visible lines of the input buffer. The viewport
    # follows the cursor so the cursor line is always visible.
    # @return [Array<String>]
    def lines
      scroll!
      visible = @rows[@scroll, height] || []
      visible.each_with_index.map do |row, i|
        (i.zero? && @scroll.zero? ? prompt : "") + row.to_s
      end
    end

    ##
    # Returns the cursor position as [line, column] within
    # the visible viewport.
    # @return [Array(Integer, Integer)]
    def cursor_pos
      scroll!
      row, col = @cursor
      col = Node.width(@rows[row].chars[0...col].map(&:to_s).join)
      col += Node.width(prompt) if row.zero?
      [row - @scroll, col]
    end

    ##
    # @return [void]
    def move_start
      @cursor = [0, 0]
    end

    ##
    # @return [void]
    def move_end
      @cursor = [@rows.size - 1, @rows.last.chars.size]
    end

    ##
    # @return [void]
    def move_left
      row, col = @cursor
      @cursor =
        if col > 0 then [row, col - 1]
        elsif row > 0 then [row - 1, @rows[row - 1].chars.size]
        else [0, 0]
        end
    end

    ##
    # @return [void]
    def move_right
      row, col = @cursor
      @cursor =
        if col < @rows[row].chars.size then [row, col + 1]
        elsif row < @rows.size - 1 then [row + 1, 0]
        else [row, col]
        end
    end

    ##
    # @return [void]
    def move_forward
      move_right
    end

    ##
    # @return [void]
    def autocomplete
      return unless text[0] == "/"
      ##
      # There are two kinds of an autocomplete
      # that can take place. The first kind
      # autocompletes command names, and the
      # second kind autocompletes command
      # arguments.
      #
      # Command arguments are given to the
      # `Command#complete(...)` method and
      # returns an array of potential candidates.
      if text.include?(" ")
        complete(:argument)
      else
        complete(:command)
      end
    end

    ##
    # @return [void]
    def kill
      row, col = @cursor
      tail = @rows[row].chars[col..].map(&:to_s).join
      tail += @rows[(row + 1)..].map(&:to_s).join("\n")
      @copy = tail
      @rows[row].chars.slice!(col..)
      @rows = @rows[0..row]
      @cursor = [row, col]
    end

    ##
    # Deletes the character at the cursor, or consumes
    # the break and pulls up the next row at the end of
    # a row.
    # @return [void]
    def delete
      row, col = @cursor
      if col < @rows[row].chars.size
        @rows[row].chars.delete_at(col)
      elsif row < @rows.size - 1
        nxt = @rows[row + 1]
        ##
        # A wrapped row was split at a space; restore it so
        # the merged words don't run together.
        @rows[row].chars << Char.new(" ") if nxt.break_type == :space
        @rows[row].chars.concat(nxt.chars)
        @rows.delete_at(row + 1)
      end
    end

    ##
    # @return [void]
    def restore
      return unless @copy
      row, col = @cursor
      @copy.each_char do |char|
        if char == "\n"
          @rows.insert(row + 1, Row.new(:newline))
          row += 1
          col = 0
        else
          @rows[row].chars.insert(col, Char.new(char))
          col += 1
        end
      end
      @cursor = [row, col]
    end

    ##
    # @return [String]
    def take
      text.tap do
        @rows = [Row.new]
        @cursor = [0, 0]
        @scroll = 0
      end
    end

    ##
    # @return [Boolean]
    def paste?
      @paste
    end

    private

    ##
    # Autocompletes command names and their arguments.
    # @param [Symbol] kind
    #  The kind of completion
    # @return [void]
    def complete(kind)
      case kind
      when :command
        fragment = text[1..]
        candidates =
          if @cache&.include?(fragment)
            @cache.candidates
          else
            LLM::Command.complete(text)
          end
        candidate = cycle(candidates, fragment)
        set(text: "/#{candidate}")
      when :argument
        name, *args = text.split(" ", -1)
        command = LLM::Command.find_by(name: name[1..])
        return unless command
        fragment, index = args.last, args.size - 1
        param = command.parameters.values.find { _1.index == index }
        return unless param
        cmd = command.new(@repl)
        candidates =
          if @cache&.include?(fragment)
            @cache.candidates
          else
            list = cmd.method(:complete).call(param.name => fragment)
            return if list.empty?
            list
          end
        candidate = cycle(candidates, fragment)
        set(text: "#{name} #{args[0..-2].compact.join(" ")} #{candidate}".squeeze(" "))
      end
    end

    ##
    # Returns the next candidate, cycling through the list
    # when the current value is already one of the candidates.
    # @param [Array<String>] candidates
    # @param [String] current
    # @return [String]
    def cycle(candidates, current)
      return "" if candidates.empty?
      index =
        if @cache and @cache.candidates == candidates
          @cache.next_index
        elsif (i = candidates.index(current))
          (i + 1) % candidates.size
        else
          0
        end
      @cache = Cache.new(candidates, index)
      @cache.value
    end

    ##
    # Adjusts @scroll so the cursor line is visible within
    # the viewport.
    def scroll!(total_lines = nil)
      total_lines ||= @rows.size
      cursor_row = @cursor[0]
      if cursor_row < @scroll
        @scroll = cursor_row
      elsif cursor_row >= (@scroll + height)
        @scroll = (cursor_row - height) + 1
      end
      @scroll = [[@scroll, (total_lines - height)].min, 0].max
    end

    def prompt
      "#{@provider}(#{@name})> "
    end

    ##
    # Returns the line the cursor is on, including the prompt.
    # @return [String]
    def current_line
      row = @cursor[0]
      (row.zero? ? prompt : "") + @rows[row].to_s
    end

    ##
    # Inserts a character at the cursor, wrapping the current row at
    # the terminal width by starting a new row. A word that would be
    # cut in half is moved whole onto the new row.
    # @param [String] char
    # @return [void]
    def insert(char)
      row, col = @cursor
      if char == "\n"
        @rows.insert(row + 1, Row.new(:newline))
        @cursor = [row + 1, 0]
      elsif Node.width(current_line) >= Curses.cols
        if char == " "
          @rows.insert(row + 1, Row.new(:space))
          @cursor = [row + 1, 0]
        elsif (index = current_line.rindex(" "))
          offset = row.zero? ? prompt.size : 0
          split = index - offset
          tail = @rows[row].chars.slice!((split + 1)..) || []
          @rows[row].chars.delete_at(split)
          @rows.insert(row + 1, Row.new(:space))
          @rows[row + 1].chars.concat(tail)
          @rows[row + 1].chars << Char.new(char)
          @cursor = [row + 1, @rows[row + 1].chars.size]
        else
          @rows.insert(row + 1, Row.new(:space))
          @rows[row + 1].chars << Char.new(char)
          @cursor = [row + 1, 1]
        end
      else
        @rows[row].chars.insert(col, Char.new(char))
        @cursor = [row, col + char.length]
      end
      scroll!
    end

    ##
    # @return [void]
    def backspace
      row, col = @cursor
      if col > 0
        @rows[row].chars.delete_at(col - 1)
        @cursor = [row, col - 1]
      elsif row > 0
        prev = @rows[row - 1]
        prev.chars.concat(@rows[row].chars)
        @rows.delete_at(row)
        @cursor = [row - 1, prev.chars.size]
      end
    end

    ##
    # Flattens the rows into a single string. Each row joins the one
    # before it using its own `break_type`: a row started by an
    # auto-wrap joins with a space, a row started by a real newline
    # joins with a newline.
    # @return [String]
    def text
      out = +""
      @rows.each_with_index do |row, i|
        out << row.to_s
        nxt = @rows[i + 1]
        if nxt
          out << (nxt.break_type == :newline ? "\n" : " ")
        end
      end
      out
    end

    ##
    # Feeds one character into the row model: newlines
    # start a row, overflowing rows wrap at a word.
    # @param [String] char
    # @return [void]
    def feed(char)
      if char == "\n"
        ##
        # A real newline is a row boundary in the model,
        # not a character, so it becomes a new row.
        @rows << Row.new(:newline)
        return
      end
      row = @rows.last
      ##
      # Only the first row shares its columns with the prompt,
      # so it has fewer columns left for text.
      width = Curses.cols - (row.equal?(@rows.first) ? Node.width(prompt) : 0)
      if row.chars.any? and Node.width(row.to_s) + 1 > width
        wrap(row)
      end
      @rows.last.chars << Char.new(char)
    end

    ##
    # Moves the word tail of a full row onto a new
    # continuation row, keeping the overflow word whole.
    # @param [LLM::Console::Input::Row] row
    # @return [void]
    def wrap(row)
      index = row.to_s.rindex(" ")
      if index
        ##
        # Move everything after the last space down and
        # drop the space; break_type restores it on flatten.
        tail = row.chars.slice!((index + 1)..) || []
        row.chars.pop
        @rows << Row.new(:space).tap { |r| r.chars.concat(tail) }
      else
        ##
        # A single unbroken word longer than the width hard-breaks.
        @rows << Row.new(:space)
      end
    end

    ##
    # Replaces the input with the given text, reflowing it into rows
    # at the terminal width. The cursor ends at the last row.
    # @param [String] text
    # @return [void]
    def set(text:)
      return if noop_set?(text)
      @rows = [Row.new]
      text.each_char { |char| feed(char) }
      ##
      # A trailing newline leaves an empty last row; drop it
      # so the cursor rests at the end of the content row.
      @rows.pop while @rows.size > 1 and @rows.last.empty?
      @cursor = [@rows.size - 1, @rows.last.chars.size]
    end

    ##
    # Returns true when the {#set} method should return early.
    # @param [String, nil] str
    #  The new string to set.
    # @return [Boolean]
    def noop_set?(str)
      if str.nil?
        true
      elsif @rows.size == 1
        chars = @rows[0].to_s
        str.empty? and chars.empty?
      else
        false
      end
    end
  end
end
