# frozen_string_literal: true

class LLM::Function
  ##
  # The {LLM::Function::Fork::Task} class wraps a fork-backed function call
  # and exchanges control and result messages with the child process.
  class Fork::Task < LLM::Function::Task
    ##
    # @param [LLM::Function] fn
    # @param [Hash] options
    # @option options [LLM::Tracer, nil] :tracer
    # @return [LLM::Function::Fork::Task]
    def initialize(fn, options = {})
      super
      @tracer = options.fetch(:tracer, nil)
      @spawned = false
      @waited = false
    end

    ##
    # @return [LLM::Function::Fork::Task]
    def spawn
      return if @guarded
      @span = @tracer&.on_tool_start(
        id: @function.id, name: @function.name,
        arguments: @function.arguments, model: @function.model
      )
      @ch = LLM::Object.from(
        control: xchan(:marshal),
        result: xchan(:marshal, sock: Socket::SOCK_STREAM)
      )
      @pid = Kernel.fork do
        ##
        # The child inherits the parent's terminal. When
        # the runtime runs under a curses REPL, a forked
        # tool reading or writing the tty would steal the
        # user's input or clobber the parent's display.
        # Point all three standard streams at null so the
        # child keeps off the user's terminal entirely. A
        # tool that genuinely needs the terminal can reopen
        # it via /dev/tty; the tty fd stays available to
        # the child.
        $stdin.reopen(File::NULL)
        $stdout.reopen(File::NULL)
        $stderr.reopen(File::NULL)
        ##
        # The child's half of the note below this block: it reads control and
        # writes result, and holds no other end.
        @ch.control.w.close
        @ch.result.r.close
        Fork::Job.new(@function, @ch).call
      end
      ##
      # Each side keeps the end it uses and closes the one it does not. Both
      # channels are socketpairs, so an end closed here is still open in the
      # child, and what the rest of them cost is a read that can never be
      # woken: a child that dies before it writes leaves this side with an
      # empty socket and - while this side is holding the write end of that
      # same pair - no end of file to say so. Closed, that is an `EOFError`,
      # and {#wait} answers with what the child ended as.
      @ch.control.r.close
      @ch.result.w.close
      @spawned = true
      self
    end

    ##
    # @return [Boolean]
    def alive?
      return false if @waited || !@pid
      status = ::Process.waitpid(@pid, ::Process::WNOHANG)
      if status
        @status = status
        @waited = true
      end
      !@waited
    rescue Errno::ECHILD
      @waited = true
      false
    end

    ##
    # @return [nil]
    def interrupt!
      return nil if @waited
      @ch.control.write(:interrupt)
      nil
    rescue Errno::ESRCH, IOError
      nil
    end
    alias_method :cancel!, :interrupt!

    ##
    # Wait for the child to write its result.
    #
    # **A second wait is answered from what the first one took.** The
    # channels are closed below, so there is nothing left to read from on a
    # second call - and a task that has answered has answered for good, which
    # is what `Thread#value` does one strategy over and what the ractor's task
    # is asserted to do. The interrupt is held the same way, as the exception
    # the first wait raised, so a second wait raises the same one rather than
    # reading a channel that has gone.
    #
    # **A child that ends without writing is named.** The ends are closed
    # above, so a channel with no writer left is an `EOFError` here rather
    # than a wait with nothing to wake it, and the child's status - a signal,
    # or the exit code of a raise it could not report - is what the caller is
    # given with it.
    # @return [LLM::Function::Return]
    def wait
      return @guarded if @guarded
      raise @result if Exception === @result
      return @result if @result
      spawn unless @spawned
      kind, data = @ch.result.recv
      @result = case kind
                when :interrupt then LLM::Interrupt.new
                when :result then Return.new(data[:id], data[:name], data[:value])
                else raise ArgumentError, "Unknown fork message: #{kind.inspect}"
                end
      raise @result if Exception === @result
      reap
      @tracer&.on_tool_finish(result: @result, span: @span)
      @result
    rescue EOFError
      reap
      raise EOFError, "the forked call ended without a result (#{@status})"
    ensure
      if @guarded.nil?
        reap
        [@ch.control, @ch.result].each { _1.close unless _1.closed? } if @ch
      end
    end
    alias_method :value, :wait

    ##
    # @return [Class]
    def group_class
      LLM::Function::Fork::Group
    end

    private

    ##
    # Waits for the child, once, and keeps what it ended as.
    # @return [Process::Status, nil]
    def reap
      return @status if @waited
      return if @guarded || !@pid
      @status = ::Process.waitpid(@pid)
      @waited = true
      @status
    rescue Errno::ECHILD
      @waited = true
      @status
    end
  end
end
