# frozen_string_literal: true

module LLM::Function::Async
  ##
  # Manages an {::Async::Reactor} on a background thread. Work
  # is submitted through a thread-safe queue and run inside the
  # reactor. The reactor and its fibers stay on one thread.
  class Reactor
    ##
    # @return [Thread]
    attr_reader :thread

    def initialize
      @inbox = Queue.new
      @thread = ::Thread.new { run }
    end

    ##
    # Submit a block to run inside the reactor.
    # @return [nil]
    def submit(&block)
      @inbox << block
      nil
    end

    ##
    # Stop the reactor and wait for the thread to finish.
    #
    # Called from a task's `wait` and from a group's `ensure`, so it has to
    # survive being called twice: a second `:stop` is a message the loop has
    # already gone, and a join on a finished thread returns at once.
    #
    # The message is sent before the thread is compared, because a reactor
    # stopped from its own thread - a tool that cancels the task it is
    # running in - still has to be stopped. Only the join would wait for
    # itself, and only the join is skipped.
    # @return [nil]
    def stop
      @inbox << :stop
      return nil if @thread == ::Thread.current
      @thread.join(5)
      @thread.kill if @thread.alive?
      nil
    end

    private

    ##
    # Run the loop until a `:stop`, then tear down. Stopping
    # cancels running children, running their ensure blocks,
    # so #run returns promptly.
    #
    # Detach the scheduler before this thread exits. Left
    # attached, Ruby calls scheduler_close on thread death,
    # and its cancel path sends a non-Exception cause: through
    # io-event's C #raise (not keyword-aware) into
    # rb_fiber_raise, which on Ruby 4.0 raises TypeError
    # (upstream async/io-event bug, not ours).
    # @return [nil]
    def run
      reactor = ::Async::Reactor.new
      reactor.async do
        loop do
          work = @inbox.pop
          if work == :stop
            reactor.stop
            break
          end
          reactor.async { work.call }
        end
      end
      reactor.run
    ensure
      ::Fiber.set_scheduler(nil)
    end
  end
end
