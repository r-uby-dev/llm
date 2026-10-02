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
  # **What differs between the strategies is the asker, not the edges.**
  # A tool that runs on a thread is interrupted by raising on that thread;
  # one that runs under a scheduler is interrupted by asking the scheduler,
  # which schedules the raise and returns. Both are one call here, and
  # everything else - the three states, and what "this call was
  # interrupted" means - is this object's, so the strategies agree about
  # where a call begins and ends.
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
      @ask = if scheduler && fiber
        -> { scheduler.fiber_interrupt(fiber, LLM::Interrupt.new) }
      else
        thread ||= ::Thread.main
        -> { thread.raise(LLM::Interrupt) }
      end
      @mutex = Mutex.new
      @changed = ConditionVariable.new
      @state = :idle
      @interrupted = false
    end

    ##
    # Called from the thread that raises - the watcher - and not from the
    # tool's.
    #
    # It waits while the window has not opened, and returns without
    # raising once it has closed. In between, the raise it issues lands on
    # the tool.
    #
    # **It waits, and that is why a scheduler strategy does not use it.**
    # The wait is a mutex and a condition variable, which is right here
    # because the caller is never the tool's thread. Where it can be - a
    # reactor, where a cancel can arrive on the thread the tool runs on -
    # {#ask!} is the one to call instead.
    #
    # What it guarantees is that the raise is not issued before the call.
    # The call's own dispatch is code, and a raise can land in that - the
    # same gap `Fork::Job` has between `running!` and `runner.call`. What
    # it does not do is issue a raise for a call that has already
    # finished: the state is read here, and the raise happens after it.
    # @return [void]
    def interrupt!
      @mutex.synchronize do
        @changed.wait(@mutex) while @state == :idle
        return unless @state == :running
        @interrupted = true
      end
      @ask.call
    end

    ##
    # Ask, if there is a call to ask about.
    #
    # **It does not wait**, which is what a strategy that runs under a
    # scheduler needs: the canceller there can be the tool's own thread,
    # and a canceller that waited for the call to start would be waiting on
    # the fiber it means to interrupt. A call that is running is asked
    # about at once; one that has already finished is a no-op; and one that
    # has not opened yet is not asked about at all - the caller reads
    # {#idle?}, waits its own way, and asks again when the call has opened.
    # @return [void]
    def ask!
      @mutex.synchronize do
        return unless @state == :running
        @interrupted = true
      end
      @ask.call
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
  end
end
