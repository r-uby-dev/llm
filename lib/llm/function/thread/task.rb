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
        # The window opens on this thread, before the call.
        #
        # It is what makes a cancel a delivery rather than a race. The
        # window is idle until `running!` below and `#interrupt!` waits on
        # it, so a cancel that arrives before this thread has reached the
        # call is held, and the raise it issues lands wherever this thread
        # is - which is the call, because nothing sits between `running!`
        # and the call but the method dispatch.
        @window = LLM::Function::Window.new(thread: ::Thread.current)
        @ready << true
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
        if @cancelled
          @delivered = true
          ::Thread.new { @window.interrupt! }
        end
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
        # On the job's own thread the hook can only run after the call's
        # frame has ended - you cannot run code on a thread blocked inside
        # a method it owns except by raising into it - and `@delivered` is
        # written before the raise and read after it, so the flag says what
        # it means. It is set wherever an interrupt is raised into a live
        # body, which includes the held cancel above. A cancel that arrives
        # once the call has finished raises nothing, and tells nobody.
        #
        # The hook runs before this thread ends, so it has run before
        # `#wait` can return - which is the other half of telling the tool
        # before the caller. A hook that raises becomes what this thread
        # returns instead, so the error reaches the caller in place of the
        # call's result.
        function.interrupt! if @delivered
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
    # @return [nil]
    def interrupt!
      @cancelled = true
      if @thread&.alive?
        @delivered = true
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
    # It is published on the queue the body fills, so a cancel that arrives
    # in the gap between the thread starting and the window existing waits
    # for the body rather than dropping itself. That wait is bounded by the
    # body's next instruction, and it is the wait the fork child's watcher
    # already makes.
    # @return [LLM::Function::Window]
    def window
      @window ||= @ready.pop
    end
  end
end
