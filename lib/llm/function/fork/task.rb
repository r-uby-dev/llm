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
      @cancelled = false
    end

    ##
    # @return [LLM::Function::Fork::Task]
    def spawn
      return if @guarded
      @span = @tracer&.on_tool_start(
        id: @function.id, name: @function.name,
        arguments: @function.arguments, model: @function.model
      )
      @ch = channels
      ##
      # **A cancel that arrived before this is written now, before the fork.**
      # The child is the reader, and it inherits both ends, so the message is
      # waiting in the channel by the time its watcher looks - which is the
      # same way a cancel that arrives a moment later is delivered, and the
      # same shape `:ractor`'s task answers with. Written earlier, it would
      # have opened a socketpair for a task that may never fork.
      if @cancelled
        @cancelled = false
        @ch.control.write(:interrupt)
      end
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
      # and {#wait} answers in band rather than waiting for a write that will
      # never come.
      @ch.control.r.close
      @ch.result.w.close
      @spawned = true
      self
    end

    ##
    # @return [Boolean]
    def alive?
      return false if @waited || !@pid
      result = ::Process.waitpid(@pid, ::Process::WNOHANG)
      @waited = !result.nil?
      !@waited
    rescue Errno::ECHILD
      @waited = true
      false
    end

    ##
    # Tells the child to stop, and is a no-op once it has answered.
    #
    # **A cancel that arrives before `spawn` is not lost.** There is no channel
    # to write to yet, so the cancel is recorded and written by `spawn`, before
    # the fork - the child is the reader, and the message waits in the channel
    # until its watcher looks, which is how a cancel that arrives a moment
    # later is delivered too.
    #
    # A task the guard blocked never forks, and one that has answered has
    # nothing left to tell: both are a no-op, the way
    # {LLM::Function::Return#interrupt!} says one is.
    # @return [nil]
    def interrupt!
      return nil if @waited || @guarded
      if @ch
        @ch.control.write(:interrupt)
      else
        @cancelled = true
      end
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
    # **A child that ended without writing is answered in band.** The ends are
    # closed above, so a channel with no writer left is an `EOFError` here
    # rather than a wait nothing can wake - and it is translated into an error
    # return the model is told about, the way the runtime answers a tool that
    # raised, rather than raised into the turn. A child that died is a call
    # that failed and the call is what should report it; ending the turn for
    # it would be an exception to the rule that a tool's failure is in band.
    # @return [LLM::Function::Return]
    def wait
      return @guarded if @guarded
      raise @result if Exception === @result
      return @result if @result
      spawn unless @spawned
      kind, data = @ch.result.recv
      @result = case kind
                when :interrupt then interrupted
                when :result then Return.new(data[:id], data[:name], data[:value])
                else raise ArgumentError, "Unknown fork message: #{kind.inspect}"
                end
      raise @result if Exception === @result
      reap
      @tracer&.on_tool_finish(result: @result, span: @span)
      @result
    rescue EOFError
      ##
      # Held in `@result` rather than answered once, so a second wait is given
      # the same return the way it is for every other ending.
      reap
      @result = Return.new(@function.id, @function.name, {
        error: true,
        type: EOFError.name,
        message: "the tool exited unexpectedly"
      })
      @tracer&.on_tool_finish(result: @result, span: @span)
      @result
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
    # The controls and results channels.
    #
    # They are built by `spawn` and not by {#interrupt!}, so a task that never
    # forks never opens a socketpair - a guard blocks many of them, and that is
    # the common case. A cancel that arrives before `spawn` is recorded instead,
    # and written by it.
    # @return [LLM::Object]
    def channels
      LLM::Object.from(
        control: xchan(:marshal),
        result: xchan(:marshal, sock: Socket::SOCK_STREAM)
      )
    end

    ##
    # Waits for the child, once.
    #
    # It is `reap` rather than a bare `waitpid` because the call appears three
    # times - the answer, the ending above, and the `ensure` - and a child can
    # only be reaped once.
    # @return [void]
    def reap
      return if @waited || @guarded || !@pid
      ::Process.waitpid(@pid)
      @waited = true
    rescue Errno::ECHILD
      @waited = true
    end

    ##
    # The ending a child reports when its call was interrupted, announced as
    # it is made rather than where it is raised.
    #
    # **One call, one ending.** `@result` holds the exception, so a caller
    # that waits twice is given the same one twice - the strategy's own spec
    # pins that - and a rescue around the raise would have told a tracer about
    # two endings for the one call. Announced here, where the exception is
    # built, the number of times it is raised cannot change the number of
    # endings a tracer hears about.
    # @return [LLM::Interrupt]
    def interrupted
      interrupt = LLM::Interrupt.new
      @tracer&.on_tool_interrupt(ex: interrupt, span: @span)
      interrupt
    end
  end
end
