# frozen_string_literal: true

class LLM::Console
  ##
  # The {LLM::Console::Color LLM::Console::Color} module returns
  # bitmasks that are understood as colors by the Curses
  # library. They can be bitwise OR'ed with other attributes,
  # such as Curses::A_BOLD.
  module Color
    ##
    # Enable color and initialize 9 color pairs.
    # @return [void]
    def self.enable
      Curses.start_color
      ##
      # The first argument is the color pairs ID, and
      # it is mapped back to a bitmask via {Curses.color_pair}.
      # The second argument is the foreground color, and
      # the third argument is the background color.
      Curses.init_pair(1, Curses::COLOR_BLACK   , Curses::COLOR_WHITE)
      Curses.init_pair(2, Curses::COLOR_BLUE    , Curses::COLOR_BLACK)
      Curses.init_pair(3, Curses::COLOR_CYAN    , Curses::COLOR_BLACK)
      Curses.init_pair(4, Curses::COLOR_GREEN   , Curses::COLOR_BLACK)
      Curses.init_pair(5, Curses::COLOR_MAGENTA , Curses::COLOR_BLACK)
      Curses.init_pair(6, Curses::COLOR_RED     , Curses::COLOR_BLACK)
      Curses.init_pair(7, Curses::COLOR_WHITE   , Curses::COLOR_BLACK)
      Curses.init_pair(8, Curses::COLOR_YELLOW  , Curses::COLOR_BLACK)
      Curses.init_pair(9, Curses::COLOR_WHITE, Curses::COLOR_BLUE)
    end

    ##
    # @return [Integer]
    def self.black
      Curses.color_pair(1)
    end

    ##
    # @return [Integer]
    def self.blue
      Curses.color_pair(2)
    end

    ##
    # @return [Integer]
    def self.cyan
      Curses.color_pair(3)
    end

    ##
    # @return [Integer]
    def self.green
      Curses.color_pair(4)
    end

    ##
    # @return [Integer]
    def self.magneta
      Curses.color_pair(5)
    end

    ##
    # @return [Integer]
    def self.red
      Curses.color_pair(6)
    end

    ##
    # @return [Integer]
    def self.white
      Curses.color_pair(7)
    end

    ##
    # @return [Integer]
    def self.yellow
      Curses.color_pair(8)
    end

    ##
    # @return [Integer]
    def self.statusbar
      Curses.color_pair(9)
    end
  end
end
