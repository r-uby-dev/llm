# frozen_string_literal: true

class LLM::Console
  ##
  # The {LLM::Console::Stream LLM::Console::Stream} class manages
  # the stream for the {LLM::Console LLM::Console} class. This class
  # has defined hooks that receive text, tool calls, and
  # tool returns.
  # @api private
  class Stream < LLM::Stream
    ##
    # @return [Hash<Symbol, LLM::Tool>]
    attr_reader :tools

    ##
    # @param [LLM::Console] console
    # @return [LLM::Console::Stream]
    def initialize(repl, queue)
      @repl = repl
      @agent = @repl.agent
      @_queue = queue
      @buffer = +""
      @tools = {}
    end

    ##
    # @param [String] chars
    #  One or more chars
    # @return [void]
    def on_content(chars)
      @buffer << chars
      @_queue.push [:stream, @buffer]
    end

    ##
    # @param [LLM::Function] tool
    # @return [void]
    def on_tool_call(tool)
      @tools[tool.name] = tool
      @_queue.push [:status, [" ", lambda, " • #{tool.name}(#{format_args(tool)})"]]
    end

    ##
    # @param [Exception] ex
    # @param [Integer] attempt
    # @return [void]
    def on_retry(ex, attempt)
      @_queue.push [:status, retry_error(ex, attempt)]
    end

    ##
    # @param [LLM::Function] tool
    # @param [LLM::Function::Return] result
    # @return [void]
    def on_tool_return(tool, result)
      @tools.delete(tool.name)
    end

    ##
    # Clear the accumulated buffer
    # @return [void]
    def clear
      @buffer.clear
    end

    private

    ##
    # @return [LLM::Agent]
    def agent
      @agent
    end

    ##
    # @return [LLM::Console::Node]
    def lambda
      Node.new("λ", Curses::A_BOLD | Color.red)
    end

    ##
    # @return [LLM::Console::Node]
    def retry_error(ex, attempt)
      err = case ex.class.to_s
      when "LLM::RateLimitError", "LLM::InsufficientQuotaError" then "Rate limited"
      when "Net::ReadTimeout", "Net::WriteTimeout", "Net::OpenTimeout" then "Timed out"
      else ex.class.to_s
      end
      [Node.new(" 🔁 "),
       Node.new("#{err} • attempt #{attempt} of #{agent.retry_budget}", Color.red | Curses::A_BOLD)]
    end

    ##
    # Formats tool arguments as compact key: value pairs
    # suitable for the status line.  Strings are quoted and
    # truncated, arrays show their first two elements, and
    # hashes collapse to `{…}`.  The whole string is capped
    # so it fits alongside the context-usage bar.
    # @param [LLM::Function] tool
    # @param [Integer] max
    # @return [String]
    def format_args(tool, max: 50)
      ##
      # 'tool.arguments' might be returned
      # (by the model) in a different order
      # than the tool definition - this code
      # handles re-sorting.
      args   = tool.arguments
      props  = tool.params.properties.keys
      props  = props.sort_by { tool.params.properties[_1].index }
      props  = props.filter_map { args[_1] ? "#{_1}: #{format_value(args[_1])}" : nil }
      result = props.join(", ")
      Node.width(result) > max ? "#{Node.slice(result, max - 1)}…" : result
    end

    ##
    # @param [Object] value
    # @param [Integer] max
    # @return [String]
    def format_value(value, max: 18)
      case value
      when String
        Node.width(value) > max ? "#{Node.slice(value, max)}…".inspect : value.inspect
      when Array
        items = value.take(2).map { format_value(_1, max: 10) }
        items << "…" if value.size > 2
        "[#{items.join(", ")}]"
      when Hash
        "{…}"
      when nil
        "nil"
      else
        str = value.inspect
        Node.width(str) > max ? "#{Node.slice(str, max)}…" : str
      end
    end
  end
end
