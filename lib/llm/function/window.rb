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
  class Window
    ##
    # @param [Thread] thread
    #  The thread the interrupt is raised on, which is the one running the
    #  tool. An argument rather than `::Thread.main` so that a strategy
    #  whose tool runs elsewhere, and a spec, can say which thread they
    #  mean.
    # @return [LLM::Function::Window]
    def initialize(thread: ::Thread.main)
      @thread = thread
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
      @thread.raise(LLM::Interrupt)
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
