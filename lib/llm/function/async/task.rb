# frozen_string_literal: true

module LLM::Function::Async
  ##
  # {LLM::Function::Async::Task} wraps a function call in an
  # {Async::Task} running on a shared
  # {LLM::Function::Async::Reactor}. The task is spawned lazily
  # in {#wait} or explicitly in {#spawn}.
  #
  # Work is submitted to the reactor through its inbox queue.
  # Results are bridged back through the task's own queue.
  class Task < LLM::Function::Task
    ##
    # @param [LLM::Function] fn
    # @param [Hash] options
    # @option options [LLM::Function::Async::Reactor] :reactor
    def initialize(fn, options = {})
      super
      @reactor = options[:reactor]
    end

    ##
    # Assign the reactor. Used when a task is created before its
    # reactor is available.
    # @param [LLM::Function::Async::Reactor] reactor
    def reactor=(reactor)
      @reactor = reactor
    end

    ##
    # Submit the function call to the reactor. The result is
    # pushed to a queue that {#wait} consumes.
    #
    # The task names itself and its scheduler from inside the reactor,
    # because neither is reachable from anywhere else: `#interrupt!` runs
    # on the caller's thread, and `Async::Task.current` is the task of the
    # *current* fiber.
    #
    # The call is wrapped in `defer_cancel`, so a cancel that arrives while
    # the tool is running is held until the block has answered. Without it,
    # the reactor's teardown can take the fiber between the tool being told
    # and the tool answering - and a tool that yields before it answers,
    # which one that saves its work does, is torn down with `Cancel`, which
    # nothing here catches and nothing pushes, leaving a caller blocked on a
    # queue that will never fill.
    #
    # The tool's hook runs from inside that block, so it runs on the
    # reactor's thread, and the result is held in a local until it has: a
    # hook that runs after the queue was pushed is a hook the caller can
    # race past.
    #
    # The rescue below is the other half of that promise, and it is written
    # to catch everything rather than an interrupt. A hook that raises from
    # the block's `ensure` unwinds past the push, so the queue would be left
    # empty and `#wait` would wait on it forever - the outcome this comment
    # already names. Whatever comes out of the block is pushed, and `#wait`
    # hands anything that is an exception to the caller the way `Thread#value`
    # and `Fiber#value` do for the other in-process strategies.
    #
    # An interrupt is the one thing that is pushed and not raised on. The
    # caller is given it through the queue, and the async runtime does not
    # read a signal as a task that failed - it reads it as the reactor's own
    # condition and ends the reactor's thread, so one cancelled tool would
    # take every sibling on that reactor with it. Every other error is raised
    # on, because a task that could not answer is one the reactor's thread
    # has to hear about.
    # @return [nil]
    def spawn
      return if @guarded
      @queue = Queue.new
      @alive = !@cancelled
      @reactor.submit do
        task = Async::Task.current
        @task = task
        @scheduler = Fiber.scheduler
        raise LLM::Interrupt if @cancelled
        task.defer_cancel do
          result = begin
            function.call
          ensure
            ##
            # The hook runs on the reactor's thread rather than on the one
            # that cancelled. See the note on
            # `LLM::Function::Thread::Task#spawn` for why it cannot run
            # before the call's frame has ended, and what `@delivered`
            # means.
            function.interrupt! if @delivered
          end
          @queue << result
        end
      rescue => e
        ##
        # This runs after the `defer_cancel` block's `ensure`, so the tool is
        # told first and the caller second. It answers an interrupt, a
        # cancel that arrived before `spawn` - the block raises before it
        # reaches a tool, and there is no result to push - and a hook whose
        # own error unwound past the push.
        @queue << e
        raise unless LLM::Interrupt === e
      end
      nil
    end

    ##
    # @return [Boolean]
    def alive?
      @alive || false
    end

    ##
    # Tells the tool, and lets it answer.
    #
    # A running tool is the one the interrupt belongs to: it handles it, or
    # it lets it raise, and either way the block above is what the caller
    # hears from - its value, or the exception it forwards.
    #
    # The tool is told from inside the reactor, not here, so that a tool
    # whose state belongs to the reactor's thread sees that thread.
    # `@delivered` is set where the raise is issued into a live fiber: a
    # cancel that arrives before the task starts, or after it has finished,
    # interrupted nothing and tells nobody.
    #
    # Nothing is done to the reactor here. Where it is stopped is `#wait`'s
    # own `ensure`, the only point at which it is known to be idle, and the
    # point a group's `wait` already stops it from: a task cannot tell
    # whether it owns its reactor or shares it with siblings, and stopping
    # one for all of them from a cancel is the wrong half of that guess.
    #
    # The fiber is checked before it is raised on because a finished task has
    # none - `Async::Task#finish!` clears it - and the scheduler does not
    # accept nil. A task that has already returned is a no-op, which is what
    # `LLM::Function::Return#interrupt!` says one is.
    # @return [nil]
    def interrupt!
      @alive = false
      @cancelled = true
      if @task&.fiber&.alive?
        @delivered = true
        @scheduler.fiber_interrupt(@task.fiber, LLM::Interrupt.new)
      elsif @task.nil? && @queue
        ##
        # A cancel before the task started: there is no tool to answer, so
        # the caller is told here, and the block raises rather than running
        # one. A cancel before `spawn` has nothing to push to, and the block
        # answers when it runs; a finish leaves nothing to say at all.
        @queue << LLM::Interrupt.new
      end
      nil
    end
    alias_method :cancel!, :interrupt!

    ##
    # Wait for the result queue to contain a value.
    #
    # It stops the reactor on the way out, which is also where a cancel's
    # cost is paid: `interrupt!` is a message and a return like every other
    # strategy's, and a tool that will not stop meets the join and the kill
    # here rather than in the caller's cancel.
    #
    # **A second wait is answered from what the first one took.** `pop` takes
    # the item, so holding it is what makes a task answerable more than once -
    # which is what `Thread#value` does for the other in-process strategy, and
    # what the ractor's task is asserted to do. The exception case is held the
    # same way, so a call that was interrupted re-raises on every wait rather
    # than raising once and then blocking on an empty queue.
    #
    # Anything that is an exception is raised rather than returned, which is
    # what `Thread#value` and `Fiber#value` do. An interrupt is the usual
    # one, and a hook that raised from the block's `ensure` is the other.
    #
    # The guarded path returns before any of that, so a task whose guard
    # blocked it does not stop a reactor it never used - which matters in a
    # group, where the reactor is not its own.
    # @return [LLM::Function::Return]
    def wait
      return @guarded if @guarded
      begin
        spawn unless @queue
        @result ||= @queue.pop
        @alive = false
        raise @result if Exception === @result
        @result
      ensure
        @reactor&.stop
      end
    end
    alias_method :value, :wait

    ##
    # @return [Class]
    def group_class
      LLM::Function::Async::Group
    end
  end
end
