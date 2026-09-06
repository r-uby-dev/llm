# frozen_string_literal: true

module LLM
  ##
  # The {LLM::Console LLM::Console} class provides a small
  # interactive console around an instance of
  # {LLM::Agent LLM::Agent}.
  #
  # It can be used to keep talking to an agent after it
  # has been set up or has performed a task. This can be
  # useful when you want to confirm the agent handled the
  # task correctly, or for it to correct course after a
  # mistake was made.
  class Console
    LLM.require "curses", "~> 1.6"
    LLM.require "kramdown", "~> 2.5"
    LLM.require "unicode/display_width", "~> 3.2"

    require_relative "console/color"
    require_relative "console/window"
    require_relative "console/status"
    require_relative "console/buffer"
    require_relative "console/input"
    require_relative "console/bar"
    require_relative "console/stream"
    require_relative "console/node"
    require_relative "console/markdown"
    require_relative "console/command"
    require_relative "console/walker"

    attr_reader :agent, :provider, :stream,
                :status, :buffer, :input,
                :window, :tools, :thread,
                :name, :path

    ##
    # @param [LLM::Agent] agent
    # @param [String, nil] name
    #  The agent's name (optional)
    # @param [String, nil] path
    #  The path where to maintain runtime state
    # @param [Array<LLM::Tool>] tools
    #  Zero or more tools
    # @param [Array<String>] skills
    #  Zero or more skills
    # @return [LLM::Console]
    def initialize(agent:, name: nil, tools: [], skills: [], path: nil)
      @path = path
      @name = name || "agent"
      @sender = "You"
      @agent = configure(agent:, path:)
      @provider = agent.llm.name
      @model = agent.model
      @input = Input.new(self, height: 3)
      @buffer = Buffer.new(self)
      @status = Status.new(self)
      @window = Window.new(self)
      @thread = nil
      @queue = Queue.new
      @stream = Stream.new(self, @queue)
      @skills = skills.map do |path|
        ##
        # I'm not sure it would make sense to expose
        # the underlying context or not. In the meantime,
        # this works and meets the expectations of the
        # LLM::Skill class.
        ctx = agent.instance_variable_get(:@ctx)
        LLM::Skill.load(path).to_tool(ctx)
      end
      @tools = [agent.params[:tools], @skills, tools].flatten.compact
    end

    ##
    # @return [void]
    def start
      window.open do
        catch(:exit) do
          write tree(agent.messages)
          loop do
            now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
            case input.on_char(window, input.paste? ? window.read_paste : window.getch, now)
            when :submit then submit
            when Symbol then window.redraw
            else
              window.redraw
              read!
              sleep 0.01
            end
          end
        end
      end
    end

    ##
    # @param [String, Array] chars
    # @param [Object] attrs
    # @param [Symbol] method (:append, :replace)
    # @return [void]
    def write(chars, attrs = nil, method: :append)
      buffer.write(chars, attrs, method:)
      window.redraw
    end

    ##
    # @param [String] user
    # @param [String] content
    # @return [void]
    def write_message(user, content, method: :append)
      buffer.write_message(user, content, method:)
      window.redraw
    end

    ##
    # Returns an AST
    # @param [String] chars
    # @return [Array<Node>]
    def markdown(chars)
      LLM::Console::Markdown.new(chars, buffer.width).ast
    end

    ##
    # @param [String] value
    # @return [void]
    def status=(value)
      status.text = value
      window.redraw
    end

    ##
    # @return [String]
    def think_text
      " 🧠 • Thinking • Esc to cancel"
    end

    ##
    # @return [String]
    def connect_text
      " 🌐 • Connecting • Esc to cancel"
    end

    ##
    # Returns a label for the person who sent a message.
    # @return [String]
    def sender
      @sender
    end

    ##
    # Returns the active model.
    # @return [String]
    def model
      @model
    end

    ##
    # Sets the active model.
    def model=(other)
      @model = other
    end

    private

    ##
    # @param [LLM::Buffer] messages
    #  A message buffer
    # @return [Array<Node>]
    def tree(messages)
      messages.flat_map do |message|
        next if message.tool_call? || message.tool_return?
        user = message.assistant? ? name : sender
        [
          Node.new("#{user}:\n", Curses::A_BOLD | Color.blue),
          *markdown(message.content),
          Node.new("\n\n")
        ]
      end.compact
    end

    ##
    # @param [LLM::Agent] agent
    #  An agent
    # @param [String] path
    #  A path
    # @raise [LLM::Error]
    #  When given an unusable path
    # @return [LLM::Agent]
    def configure(agent:, path:)
      if path.nil?
        agent
      elsif !File.exist?(path)
        File.write path, "{}"
        agent
      elsif restore?
        agent.restore(path:)
      else
        raise LLM::Error, "I can't use '#{path}' - " \
                          "it should be both readable and writable"
      end
    end

    ##
    # This method is called when the user submits their input.
    # It spawns a second thread that maintains a line of
    # communication with a model and the main thread - where
    # the UI runs - remains responsive.
    # @api private
    def submit
      return if thread&.alive? || (text = input.take).empty?
      case on_text(text)
      in [:command, Command => command, Hash => parameters]
        command.call(**parameters)
      in [:error, String => user, String => text]
        write_message(user, text)
      in [:input, String => text]
        window.scroll_to_bottom
        status.text = connect_text
        write_message(sender, markdown(text))
        @thread = Thread.new do
          @queue << [:start]
          agent.talk(text, model:, tools:, stream:)
          agent.save(path:) if save?
          @queue << [:done]
        rescue LLM::Interrupt => e
          @queue << [:cancel, e]
        rescue => e
          @queue << [:error, e]
        end
      end
    end

    ##
    # Receives user input and determines what codepath
    # it should follow - either executing a command,
    # or sending a string to the model.
    # @param [String] text
    # @return [[Symbol, Command|String]]
    def on_text(text)
      command = Command.find_by(input: text)
      if command
        parameters = command.parameters.map { [_1, _2.dup] }.to_h
        args = text.split(" ")[1..].reject(&:empty?)
        reqc = parameters.values.count(&:required?)
        if args.size < reqc
          [:error,
           "command(#{command.name}): ",
           "too few arguments: expected #{reqc} but got #{args.size}\n\n"]
        else
          parameters = parameters.sort_by(&:index).to_h
          kwargs = {}
          parameters.each_value do |parameter|
            if args[parameter.index]
              kwargs[parameter.name] = args[parameter.index]
            end
          end
          [:command, command.new(self), kwargs]
        end
      else
        [:input, text]
      end
    end

    ##
    # This method reads from the queue that is written to
    # by a second thread. The queue is managed or written
    # to by a subclass of {LLM::Stream LLM::Stream}.
    # @api private
    def read!
      loop do
        type, value = @queue.pop(true)
        case type
        when :start
          buffer.open
          stream.clear
        when :stream
          status.text = think_text if stream.tools.empty?
          write_message name, markdown(value), method: :replace
        when :status
          self.status = value
        when :done
          status.text = "idle"
          buffer.close
          @thread = nil
        when :cancel
          stream.tools.clear
          buffer.close
          status.text = "Idle"
          write_message(name, "Request cancelled")
          @thread = nil
        when :error
          status.text = "error"
          write_message(name, "(#{value.class}): #{value.message}")
          buffer.close
          @thread = nil
        end
      end
    rescue ThreadError
    end

    ##
    # @return [Boolean]
    def restore?
      return false if path.nil?
      File.writable?(path)
    end

    ##
    # @return [Boolean]
    def save?
      return false if path.nil?
      File.readable?(path)
    end

    File = ::File
    private_constant :File
  end

  ##
  # Alias: LLM::Repl
  Repl = Console
end
