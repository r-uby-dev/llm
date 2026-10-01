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
  # dropped, and delivered when the thread does. The thread is
  # created with `report_on_exception` disabled so unhandled
  # exceptions propagate through {#wait} instead of to stderr.
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
      @thread = ::Thread.new do
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
        # it means. It is set wherever a raise was issued into a live
        # thread, which includes the cancel that arrived before this thread
        # existed: that one is held, and {#deliver!} raises it. A cancel
        # that arrives once the call has finished interrupted nothing, and
        # tells nobody - which is the no-op that
        # {LLM::Function::Return#interrupt!} already is.
        #
        # The hook runs before this thread ends, so it has run before
        # `#wait` can return - which is the other half of telling the tool
        # before the caller. A hook that raises becomes what this thread
        # returns instead, so the error reaches the caller in place of the
        # call's result.
        function.interrupt! if @delivered
      end
      @thread.report_on_exception = false
      deliver!
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
        @thread.raise(LLM::Interrupt)
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
    # Spends a cancel that was held rather than dropped.
    #
    # A cancel that arrives before the thread exists has nothing to be
    # raised on, so it is recorded, and this is where it is delivered: the
    # thread is live by the time this runs, and a raise into a thread that
    # has not started is delivered at its first instruction, which is the
    # call. A thread that has already finished is left alone, which is the
    # cancel that arrives too late to be anything but a no-op.
    # @return [nil]
    def deliver!
      if @cancelled && @thread&.alive?
        @delivered = true
        @thread.raise(LLM::Interrupt)
      end
      nil
    end
  end
end
