# frozen_string_literal: true

class LLM::Console
  ##
  # The {LLM::Console::Status LLM::Console::Status} class stores
  # the small status line shown at the top of the REPL.
  #
  # The status text can be a plain String, a single
  # {LLM::Console::Node LLM::Console::Node} (text plus curses attributes),
  # or an Array of either. Attributes on nodes are applied when the
  # window draws the status line.
  # @api private
  class Status
    ##
    # @param [LLM::Console] console
    # @return [LLM::Console::Status]
    def initialize(repl)
      @repl = repl
      @agent = repl.agent
      @provider = @agent.llm.name
      @nodes = [Node.new("idle")]
    end

    ##
    # @return [String]
    def context_bar
      LLM::Console::Bar.new(
        ##
        # After compaction the used context is unknown until the next
        # response, so the bar renders an unknown state instead of a
        # stale percentage.
        fraction: @agent.compacted? ? nil : @agent.context_usage
      ).to_s
    end

    ##
    # @return [String]
    def cost
      "$#{@agent.cost} "
    end

    ##
    # Returns the current model in use.
    # @return [LLM::Console::Node]
    def model
      Node.new @repl.model.to_s, Curses::A_BOLD
    end

    ##
    # Returns the current working directory.
    # @return [LLM::Console::Node]
    def cwd
      Node.new Dir.pwd.sub(Dir.home, "~"), Curses::A_BOLD
    end

    ##
    # Sets the status text.
    # @param [String, LLM::Console::Node, Array<String, LLM::Console::Node>] value
    # @return [Array<LLM::Console::Node>]
    def text=(value)
      @nodes =
        case value
        when Node then [value]
        when Array then value.map { |node| Node === node ? node : Node.new(node) }
        else [Node.new(value)]
        end
    end

    ##
    # @return [String]
    def text
      @nodes.map(&:text).join
    end

    ##
    # @return [String]
    alias_method :to_s, :text

    ##
    # The nodes making up the status line.
    # @return [Array<LLM::Console::Node>]
    def nodes
      if @agent.compacted?
        [Node.new("Context compacted")]
      else
        @nodes
      end
    end
  end
end
