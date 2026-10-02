# frozen_string_literal: true

module LLM::Function::Thread
  ##
  # {LLM::Function::Thread::Task LLM::Function::Thread::Task}
  # wraps a function call in a background thread for concurrent
  # tool execution. The thread is created lazily when {#wait} is
  # called, not when the task is constructed — so you can build
  # a task, pass it around, and decide when to run it.
  #
  # Interrupting a running task raises {LLM::Interrupt} inside
  # the thread, which stops the tool call mid-flight. A cancel
  # that arrives before the thread exists is held rather than
  # dropped, and spent inside the call: the tool is entered, so a
  # tool whose own `rescue LLM::Interrupt` cleans up is cleaned up
  # by a cancel that arrived before it started, the way it is on
  # `:fork` and `:ractor`. The thread is created with
  # `report_on_exception` disabled so unhandled exceptions
  # propagate through {#wait} instead of to stderr.
  #
  # A tool that implements `on_interrupt` is told on that thread, once
  # the call has ended, rather than on the thread that cancelled it.
  class Task < LLM::Function::Task
    ##
    # @param [LLM::Function] fn
    # @param [Hash] options
    def initialize(fn, options = {})
      super
    end

    ##
    # @return [nil]
    def spawn
      return if @guarded
      @ready = Queue.new
      @thread = ::Thread.new do
        ##
        # The window opens on this thread, before the call, and it is
        # published on the queue a canceller may already be waiting on.
        #
        # It is what makes a cancel a delivery rather than a race. The
        # window is idle until `running!` below and `#interrupt!` waits on
        # it, so a cancel that arrives before this thread has reached the
        # call is held rather than dropped - and the raise it issues is not
        # issued before the call, which is what puts it at the tool in
        # practice.
        @window = LLM::Function::Window.new(thread: ::Thread.current)
        @ready << @window
        ##
        # **A cancel that arrived before this thread existed is delivered
        # by a watcher of its own.**
        #
        # `#interrupt!` was answered before there was a thread to raise on,
        # so this is the only place left that can hold the cancel - and
        # raising it here is raising it before the call, which is what this
        # task used to do: the tool was never entered, so a tool whose own
        # rescue cleans up was never cleaned up. The window holds it
        # instead, and opens on the call.
        ::Thread.new { @window.interrupt! } if @cancelled
        @window.running!
        function.call
      ensure
        ##
        # The window closes before the hook runs, so a cancel that arrives
        # once the call has returned finds nothing to interrupt - which is
        # the no-op {LLM::Function::Return#interrupt!} already says one is.
        @window&.finished!
        ##
        # The hook runs on this thread rather than on the one that
        # cancelled, because a tool's state belongs to the thread its call
        # runs on, and the caller's thread is not that thread.
        #
        # It runs for a call that was interrupted and not for a call that
        # was asked about: the window is the frame that decides whether a
        # raise is issued, so it is the frame that knows, and
        # `Window#interrupted?` is true only where the raise was. A cancel
        # that arrives while the call is returning, and a held cancel whose
        # tool finished before the watcher was scheduled, are both cancels
        # that interrupted nothing - and neither tells the tool.
        #
        # On the job's own thread the hook can only run after the call's
        # frame has ended - you cannot run code on a thread blocked inside
        # a method it owns except by raising into it - so it runs here
        # rather than before the raise, as `:fork` runs it.
        #
        # The hook runs before this thread ends, so it has run before
        # `#wait` can return - which is the other half of telling the tool
        # before the caller. A hook that raises becomes what this thread
        # returns instead, so the error reaches the caller in place of the
        # call's result.
        function.interrupt! if @window&.interrupted?
      end
      @thread.report_on_exception = false
      nil
    end

    ##
    # @return [Boolean]
    def alive?
      @thread&.alive? || false
    end

    ##
    # Asks the tool to stop, and waits for it to be possible.
    #
    # **It can wait, and the waits are bounded by the body's next
    # instruction.** One is for the window itself - the body publishes it on
    # `@ready` before it opens the call - and one is inside the window,
    # which holds the raise until the call is running. A task this method
    # was called on before it had a thread is the exception: the cancel is
    # recorded and the body delivers it, because there is nothing here to
    # raise on yet.
    #
    # A group and `Context#interrupt!` call this in a loop, which is why the
    # wait is worth a line: a loop's cost is the longest wait in it, and
    # every one of those is a dispatch wide.
    # @return [nil]
    def interrupt!
      @cancelled = true
      if @thread&.alive?
        window.interrupt!
      end
      nil
    end
    alias_method :cancel!, :interrupt!

    ##
    # @return [LLM::Function::Return]
    def wait
      return @guarded if @guarded
      spawn unless @thread
      @thread.value
    end
    alias_method :value, :wait

    ##
    # @return [Class]
    def group_class
      LLM::Function::Thread::Group
    end

    private

    ##
    # The window the body opened, from wherever it is.
    #
    # The body publishes it on a queue before it opens the call, so a
    # cancel that arrives in the gap between the thread starting and the
    # window existing waits for the body rather than dropping itself. That
    # wait is bounded by the body's next instruction, and it is the wait
    # the fork child's watcher already makes.
    # @return [LLM::Function::Window]
    def window
      @window ||= @ready.pop
    end
  end
end
