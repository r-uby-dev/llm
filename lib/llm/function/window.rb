# frozen_string_literal: true

class LLM::Function
  ##
  # The stretch of a call that an interrupt belongs to.
  #
  # A raise cannot be aimed at a region of code, only permitted for one -
  # it lands wherever the thread it targets happens to be. This is what
  # permits it: an interrupt that arrives while the tool is running is
  # raised on the tool at once, and one that arrives before the tool runs
  # is held until it does, where the tool's own `rescue` can have it.
  #
  # Held rather than answered, because arriving early is not the same as
  # being declined: the tool has not had its chance yet. And afterwards
  # there is nothing to interrupt - a cancel that arrives once the work is
  # finished is a no-op, which is what
  # {LLM::Function::Return#interrupt!} already says one is.
  #
  # **What differs between the strategies is how the raise is issued, not
  # where the edges are.** A tool that runs on a thread is interrupted by
  # raising on that thread; one that runs under a scheduler is interrupted
  # by asking the scheduler, which schedules the raise and returns. Both
  # are one call here, and everything else - the three states, and what
  # "this call was interrupted" means - is this object's, so the strategies
  # agree about where a call begins and ends.
  class Window
    ##
    # @param [Thread, nil] thread
    #  The thread the interrupt is raised on, which is the one running the
    #  tool. An argument rather than `::Thread.main` so that a strategy
    #  whose tool runs elsewhere, and a spec, can say which thread they
    #  mean.
    # @param [Object, nil] scheduler
    #  A scheduler to ask instead of a thread to raise on - the
    #  `Fiber.scheduler` a tool that runs under one was given. Asking is
    #  not raising: `fiber_interrupt` schedules the raise and returns, so a
    #  canceller that is the tool's own thread is not left waiting on it. A
    #  scheduler that does not implement it - it is new enough that few do -
    #  is asked by raising on the fiber directly, which suspends the
    #  canceller until the scheduler delivers it.
    # @param [Fiber, nil] fiber
    #  The fiber the scheduler is asked to raise on, which is the one
    #  running the tool.
    # @return [LLM::Function::Window]
    def initialize(thread: nil, scheduler: nil, fiber: nil)
      @raise = interrupt_for(thread:, scheduler:, fiber:)
      @mutex = Mutex.new
      @changed = ConditionVariable.new
      @state = :idle
      @deferred = false
      @interrupted = false
    end

    ##
    # Asks the call to stop, waiting for it to start if this canceller can
    # afford to.
    #
    # The wait is a mutex and a condition variable, and whether it can be
    # taken is the whole of what `wait` is for: the canceller is never the
    # tool's thread on `:thread`, `:fork` and `:ractor`, so it waits, and
    # it can be on a reactor - where a cancel can arrive on the thread the
    # tool runs on - so there it does not.
    #
    # **A call that has not opened is not asked about, and the ask is not
    # lost.** With `wait: false` the ask is recorded and issued when the
    # call opens, which is the transition {#running!} alerts - the only
    # place that can, since the caller cannot wait and the call has not
    # begun. Without that record the strategies disagree: `:thread`
    # delivers an ask made in this moment, and a scheduled strategy drops
    # it.
    #
    # A call that is running is asked about at once, and one that has
    # finished asks nothing. The raise is not issued before the call - the
    # call's own dispatch is code, and a raise can land in that, the same
    # gap `Fork::Job` has between `running!` and `runner.call` - and it is
    # not issued for a call that has already finished.
    # @param [Boolean] wait
    #  Whether to wait for the call to open.
    # @return [void]
    def interrupt!(wait: true)
      issue = @mutex.synchronize do
        @changed.wait(@mutex) while wait and @state == :idle
        if @state == :idle
          @deferred = true
          false
        elsif @state == :running
          @interrupted = true
          true
        else
          false
        end
      end
      @raise.call if issue
    end

    ##
    # Whether the call has not opened yet.
    # @return [Boolean]
    def idle?
      @mutex.synchronize { @state == :idle }
    end

    ##
    # Whether the call is running.
    # @return [Boolean]
    def running?
      @mutex.synchronize { @state == :running }
    end

    ##
    # Whether a raise has been issued for this call.
    #
    # A caller that has to decide whether to tell a tool that it was
    # cancelled asks this rather than reading a flag of its own: the window
    # is the frame that decides whether a raise is the tool's to handle, so
    # it is the frame that knows. It is true where a raise was issued, and
    # false where none was - a call that has finished, and a cancel that
    # arrived without one.
    #
    # **Issued, not delivered, and the two are not the same here.** A
    # strategy that asks a scheduler gets a raise that is scheduled rather
    # than one that has landed - and a tool that never suspends is one it
    # cannot land inside, so that tool is asked about and never reached.
    # The flag is the notification that an ask was taken up, not a promise
    # that the tool saw it, and a caller that needs the second has to get
    # it from the tool.
    # @return [Boolean]
    def interrupted?
      @mutex.synchronize { @interrupted }
    end

    ##
    # Called from the tool's thread, immediately before the call.
    #
    # It does not wait for the watcher: it changes the state and returns,
    # so the thread that is about to call the tool stays ahead of the
    # thread that is about to interrupt it. By the time the watcher is
    # scheduled, the tool is running.
    #
    # An ask that could not wait is issued here, after the state has been
    # changed and the lock released - so a caller that cannot wait is
    # still answered, and answered once.
    # @return [void]
    def running!
      issue = @mutex.synchronize do
        @state = :running
        @changed.broadcast
        if @deferred
          @deferred = false
          @interrupted = true
        else
          false
        end
      end
      @raise.call if issue
    end

    ##
    # Called from the tool's thread, once it has returned - in the happy
    # path before the result is written, and in `ensure` for every other.
    # Wakes anyone holding an interrupt, who then finds there is nothing
    # to interrupt.
    # @return [void]
    def finished!
      @mutex.synchronize do
        @state = :finished
        @changed.broadcast
      end
    end

    private

    ##
    # The callable that issues the raise, built from whichever the strategy
    # gave.
    #
    # Either a thread to raise on - the default being `::Thread.main`, so
    # that a strategy whose tool runs elsewhere can name its own - or a
    # scheduler and the fiber it is asked to raise on. The two go together:
    # one without the other would fall back to raising on `::Thread.main`,
    # which under a reactor is the thread the tool runs on.
    # @param [Thread, nil] thread
    # @param [Object, nil] scheduler
    # @param [Fiber, nil] fiber
    # @return [Proc]
    def interrupt_for(thread:, scheduler:, fiber:)
      if scheduler and fiber
        if scheduler.respond_to?(:fiber_interrupt)
          -> { scheduler.fiber_interrupt(fiber, LLM::Interrupt.new) }
        else
          -> { fiber.raise(LLM::Interrupt) }
        end
      elsif scheduler or fiber
        raise ArgumentError, "a scheduler and a fiber are given together"
      else
        thread ||= ::Thread.main
        -> { thread.raise(LLM::Interrupt) }
      end
    end
  end
end
