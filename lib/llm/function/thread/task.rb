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
  # dropped, and spent by the thread itself when it starts. The
  # thread is created with `report_on_exception` disabled so
  # unhandled exceptions propagate through {#wait} instead of to
  # stderr.
  #
  # A tool that implements `on_interrupt` is told on that thread, once
  # the call has ended, rather than on the thread that cancelled it.
  class Task < LLM::Function::Task
    ##
    # @param [LLM::Function] fn
    # @param [Hash] options
    def initialize(fn, options = {})
      super
      ##
      # Serialises the cancel against the start of the body. The record is
      # written under this lock and read under it, so a cancel can neither
      # pass the read nor be passed by it: it is spent by the body or raised
      # by the canceller, and never neither.
      @mutex = Mutex.new
    end

    ##
    # @return [nil]
    def spawn
      return if @guarded
      ##
      # The lock is held from before the thread exists until it is named and
      # quiet, so the body's first instruction - the read below - cannot be
      # ordered before the assignment of `@thread`. A canceller waiting for
      # the lock therefore finds a record to spend or a thread to raise on,
      # and no third thing.
      @mutex.synchronize do
        @started = false
        @thread = ::Thread.new do
          ##
          # A cancel that arrived before this thread existed is spent here,
          # rather than raised in from the outside.
          #
          # **A raise into a thread that has not started is delivered at its
          # first checkpoint**, and whether that arrives before this block's
          # `ensure` is active or inside it is not something a caller can
          # rely on - raising in from outside delivered the interrupt, ended
          # the thread with it, and ran no hook at all. Here the block is
          # running, so the hook below follows this raise the same way it
          # follows a call.
          #
          # `@started` is what keeps the two halves of the cancel apart. It is
          # set in the same critical section as the read, so a canceller that
          # finds it true is talking to a body that has read the record, and
          # one that finds it false has already written the record that this
          # read spends.
          cancelled = @mutex.synchronize do
            @started = true
            @cancelled
          end
          if cancelled
            @delivered = true
            raise LLM::Interrupt
          end
          function.call
        ensure
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
          # once the call has finished raises nothing, and tells nobody -
          # which is the no-op that {LLM::Function::Return#interrupt!}
          # already is.
          #
          # The hook runs before this thread ends, so it has run before
          # `#wait` can return - which is the other half of telling the tool
          # before the caller. A hook that raises becomes what this thread
          # returns instead, so the error reaches the caller in place of the
          # call's result.
          function.interrupt! if @delivered
        end
        @thread.report_on_exception = false
      end
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
      @mutex.synchronize do
        @cancelled = true
        ##
        # A body that has read the record is told by a raise; one that has not
        # is told by the record, and spends it as its first instruction. Both
        # are issued under the lock, so `@delivered` and the raise stay
        # together, and neither can be ordered before the body's read.
        if @started && @thread&.alive?
          @delivered = true
          @thread.raise(LLM::Interrupt)
        end
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
  end
end
