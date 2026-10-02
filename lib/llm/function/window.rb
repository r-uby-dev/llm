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
    #  canceller that is the tool's own thread is not left waiting on it.
    # @param [Fiber, nil] fiber
    #  The fiber the scheduler is asked to raise on, which is the one
    #  running the tool.
    # @return [LLM::Function::Window]
    def initialize(thread: nil, scheduler: nil, fiber: nil)
      @interrupt = define_interrupt!(thread:, scheduler:, fiber:)
      @mutex = Mutex.new
      @changed = ConditionVariable.new
      @state = :idle
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
    # tool runs on - so there it does not, and the caller waits its own way
    # and asks again once the call has opened.
    #
    # Either way: a call that has not opened is not asked about, one that
    # is running is asked about at once, and one that has finished asks
    # nothing. The raise is not issued before the call - the call's own
    # dispatch is code, and a raise can land in that, the same gap
    # `Fork::Job` has between `running!` and `runner.call` - and it is not
    # issued for a call that has already finished.
    # @param [Boolean] wait
    #  Whether to wait for the call to open.
    # @return [void]
    def interrupt!(wait: true)
      @mutex.synchronize do
        @changed.wait(@mutex) while wait and @state == :idle
        return unless @state == :running
        @interrupted = true
      end
      @interrupt.call
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
    # Whether this window has issued an interrupt.
    #
    # A caller that has to tell *asked* from *delivered* asks this rather
    # than reading a flag of its own: the window is the frame that decides
    # whether a raise is the tool's to handle, so it is the frame that
    # knows. It is true only where the raise was issued, which is never
    # once the state is `finished`.
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
    # @return [void]
    def running!
      @mutex.synchronize do
        @state = :running
        @changed.broadcast
      end
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
    # scheduler and the fiber it is asked to raise on.
    # @param [Thread, nil] thread
    # @param [Object, nil] scheduler
    # @param [Fiber, nil] fiber
    # @return [Proc]
    def define_interrupt!(thread:, scheduler:, fiber:)
      if scheduler and fiber
        -> { scheduler.fiber_interrupt(fiber, LLM::Interrupt.new) }
      else
        thread ||= ::Thread.main
        -> { thread.raise(LLM::Interrupt) }
      end
    end
  end
end
