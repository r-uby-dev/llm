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
    # **The window is this strategy's whole answer to a cancel that arrived
    # early.** It is built with the scheduler as what raises, so the raise
    # is asked for rather than issued here, and its states and `interrupted?`
    # are what this task reads instead of a state of its own. A cancel that
    # arrived before the block ran, and one that arrives while the block is
    # between its check and the call, are both asks the window holds until
    # the call opens.
    #
    # `LLM::Interrupt` is a subclass of `Exception`, and one that is left to
    # raise kills the reactor's thread and takes every other task on that
    # reactor with it. So the task rescues it, stores it on its own queue,
    # and exits silently - and the caller reads the queue and raises the
    # interrupt on its own thread or fiber, which is where it was asked for.
    #
    # The rescue below names the interrupt rather than leaving it to a bare
    # rescue, because a bare rescue - and `rescue => e` - reaches only
    # `StandardError`.
    # @return [nil]
    def spawn
      return if @guarded
      @queue = Queue.new
      @alive = !@cancelled
      @reactor.submit do
        task = Async::Task.current
        @task = task
        @scheduler = Fiber.scheduler
        @window = LLM::Function::Window.new(scheduler: @scheduler, fiber: task.fiber)
        ##
        # A cancel that arrived before this block ran. There is nothing to
        # ask for yet, so the ask is recorded and issued when the call opens
        # - which is the transition the window alerts, and the only place
        # that can, since this fiber is the one that will be running the
        # tool.
        @window.interrupt!(wait: false) if @cancelled
        task.defer_cancel do
          result = begin
            ##
            # The call opens here, and it is what a deferred ask is issued
            # against. What the window guarantees is that the raise is not
            # asked for before the call; the dispatch itself is code, and a
            # raise can land in it, which is the same gap `Fork::Job` has
            # between `running!` and `runner.call`.
            @window.running!
            function.call
          rescue LLM::Interrupt => ex
            ##
            # The interrupt is the block's result, and the queue carries it
            # to the caller.
            ex
          ensure
            ##
            # The tool has answered, so a cancel that arrives from here on
            # asks nothing - which is the no-op a cancel that arrives once
            # the call has returned is.
            @window.finished!
            ##
            # The hook runs on the reactor's thread rather than on the one
            # that cancelled. See the note on
            # `LLM::Function::Thread::Task#spawn` for why it cannot run
            # before the call's frame has ended, and what the window's
            # `interrupted?` means.
            function.interrupt! if @window.interrupted?
          end
          @queue << result
        end
      rescue LLM::Interrupt, StandardError => e
        ##
        # This runs after the `defer_cancel` block's `ensure`, so the tool is
        # told first and the caller second. It answers a hook whose own
        # error unwound past the push, and it is the backstop for an
        # interrupt that arrived from somewhere other than the call above -
        # which is why the interrupt is pushed and not raised on.
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
    #
    # **The ask is the window's, from wherever it is made.** This runs on
    # the caller's thread, which can be the reactor's, so it asks without
    # waiting: a call that is running is asked about at once, one that has
    # finished asks nothing, and one that has not opened holds the ask until
    # it does. A cancel that arrived before the block ran is the same ask,
    # made by the block.
    #
    # Nothing is done to the reactor here. Where it is stopped is `#wait`'s
    # own `ensure`, the only point at which it is known to be idle, and the
    # point a group's `wait` already stops it from: a task cannot tell
    # whether it owns its reactor or shares it with siblings, and stopping
    # one for all of them from a cancel is the wrong half of that guess.
    # @return [nil]
    def interrupt!
      @alive = false
      @cancelled = true
      @window&.interrupt!(wait: false)
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
