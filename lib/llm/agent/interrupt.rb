# frozen_string_literal: true

class LLM::Agent
  ##
  # Stop an agent in its tracks.
  #
  # The {LLM::Agent::Interrupt} module extends
  # the instance variable `@caller` (an instance
  # of {LLM::Object}) that belongs to an agent
  # and its context.
  #
  # The `@caller` instance variable captures the
  # agent's thread, fiber, and scheduler. The
  # variable is in scope for as long as an agent
  # is running and it provides other threads and
  # fibers with access to the agent's thread,
  # fiber and scheduler.
  #
  # A different thread or fiber can use this module
  # and the object it extends (`@caller`) to stop
  # an agent in its tracks via the raise of
  # {LLM::Interrupt LLM::Interrupt} on the
  # agent's thread, or fiber.
  #
  # @note
  #  The method provided by this module is
  #  not called directly, and the `@caller`
  #  instance variable is private. The
  #  {LLM::Agent#interrupt!} and {LLM::Context#interrupt!}
  #  methods call it on your behalf.
  #
  # @see LLM::Agent#run_loop
  # @see LLM::Context#interrupt!
  module Interrupt
    ##
    # Stops an agent in its tracks.
    #
    # When this method is called from
    # the agent's thread but a different
    # fiber an interrupt is raised on the
    # caller's fiber.
    #
    # And when it is called from a thread
    # other than the agent's thread, the
    # interrupt is raised on the caller's
    # thread.
    #
    # @return [void]
    def interrupt!
      if thread.equal?(Thread.current)
        if fiber
          if scheduler
            scheduler.fiber_interrupt(fiber, LLM::Interrupt.new("agent interrupted"))
          else
            fiber.raise(LLM::Interrupt, "agent interrupted")
          end
        end
      else
        thread.raise(LLM::Interrupt, "agent interrupted")
      end
      nil
    rescue ThreadError, FiberError
      nil
    end
  end
end
