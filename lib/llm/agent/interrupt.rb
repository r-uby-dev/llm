# frozen_string_literal: true

class LLM::Agent
  ##
  # What a turn's caller answers to.
  #
  # A turn is a loop, and between two of its requests there is nothing in
  # flight to close and nothing running to raise into. {LLM::Agent#run_loop}
  # records where it is running - the thread, the fiber, the scheduler that
  # fiber belongs to, and the tracer the turn is traced with - and extends
  # this onto that record, so an interrupt with nothing more precise to do
  # has somewhere to land: {LLM::Context#interrupt!} calls `interrupt!` on
  # the caller it holds, and what the caller does with the names is its own
  # business.
  #
  # It is public rather than private because the runtime is not the only
  # thing that runs a loop: an application with a loop of its own can record
  # a caller the same way, and a spec can build one without running a turn.
  # @see LLM::Agent#run_loop
  # @see LLM::Context#interrupt!
  module Interrupt
    ##
    # Ends the turn where it is, and tells the tracer first.
    #
    # Which name receives the raise is decided by who is cancelling:
    #
    #   another thread  the thread, because a fiber belongs to the thread
    #                   that made it and cannot be entered from another
    #                   one. The raise lands in whichever fiber that
    #                   thread is running, which is the turn's, because
    #                   the turn is what it is doing.
    #
    #   the same thread the fiber, because raising on the thread would
    #                   raise in the canceller that asked for it.
    #
    # A fiber scheduler is the case the second rule is for: a turn under
    # Falcon or Async runs on a fiber of the reactor's thread, and a cancel
    # that arrives on that thread is another fiber asking. Such a fiber is
    # asked for through the scheduler, the way
    # {LLM::Function::Fiber::Task#interrupt!} asks, because a direct raise
    # into a scheduled fiber does not transfer: it suspends the thread that
    # raises, and that thread is the canceller's. A fiber with no scheduler
    # behind it - a turn an application ran in a fiber of its own - is raised
    # into directly, which is what such a fiber is for.
    #
    # The tracer is told `scope: :agent`, before the raise, the way
    # {LLM::Context#wait} tells it `scope: :tool` before the caller is given
    # that interrupt. A tracer that has to account for every interrupt a turn
    # receives needs this one too, and the alternative - announcing it from
    # the turn as it unwinds - is not available: between two requests there
    # is no frame of the turn's own to announce it from.
    #
    # Nothing is raised, and nothing is announced, when there is no fiber to
    # raise into - and nothing is raised when the turn ended between the read
    # and the raise, which is the ordinary race, because a cancel that
    # arrives after a turn is not a failure.
    # @return [nil]
    def interrupt!
      if thread.equal?(Thread.current)
        if fiber
          tracer&.on_interrupt(scope: :agent)
          if scheduler
            scheduler.fiber_interrupt(fiber, LLM::Interrupt.new("agent interrupted"))
          else
            fiber.raise(LLM::Interrupt, "agent interrupted")
          end
        end
      else
        tracer&.on_interrupt(scope: :agent)
        thread.raise(LLM::Interrupt, "agent interrupted")
      end
      nil
    rescue ThreadError, FiberError
      nil
    end
  end
end
