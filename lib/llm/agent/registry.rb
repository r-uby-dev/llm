# frozen_string_literal: true

class LLM::Agent
  ##
  # {LLM::Agent::Registry LLM::Agent::Registry} holds the agents that are
  # running a turn in this process, so that a cancel can find one.
  #
  # Delivery is not the problem it solves. `LLM::Agent#interrupt!` can be
  # called from any thread, and {LLM::Agent::Interrupt LLM::Agent::Interrupt}
  # decides what receives the raise - but a canceller has to hold the agent,
  # and in an application the agent is built inside the job that runs the
  # turn and stays a local variable for as long as the turn lasts. A cancel
  # button has nothing to reach.
  #
  # So a turn registers itself for as long as it runs, and a canceller names
  # the identity it already has: the record's id when the agent was built
  # around one, the agent's own id otherwise.
  #
  # ## What it does not promise
  #
  # It is **one process**, and it holds the agents *that process* is running.
  # A cancel that lands elsewhere - a second worker, a deploy that leaves two
  # up for a minute - finds nothing, and `false` must not be read as "the turn
  # is over". An application that needs a guarantee keeps one of its own; this
  # is the fast path.
  #
  # @api private
  class Registry
    ##
    # @return [LLM::Agent::Registry]
    def initialize
      @agents = {}
      @mutex  = Mutex.new
    end

    ##
    # Records that an agent is running a turn.
    #
    # Strongly, and that is the point: an entry has to reach an agent that
    # is blocked inside `talk`, so a weak reference would let a turn that is
    # running be collected. The lifetime is the caller's `ensure`.
    # @param [LLM::Agent] agent
    # @return [LLM::Agent]
    #  Returns the agent
    def enter(agent)
      @mutex.synchronize { @agents[key(agent)] = agent }
      agent
    end

    ##
    # Records that an agent's turn is over.
    #
    # Removed only if it is still the agent that registered. Two turns under
    # one identity - a second attempt alongside one that is finishing - are
    # not the same turn, and the one that finishes first must not take the
    # other one's registration with it.
    # @param [LLM::Agent] agent
    # @return [void]
    def exit(agent)
      @mutex.synchronize do
        id = key(agent)
        @agents.delete(id) if @agents[id].equal?(agent)
      end
    end

    ##
    # The agent running a turn under this identity, or nil.
    #
    # Looked up under the lock and answered outside it, because the
    # interrupt that follows is not this class's to make: a caller holding
    # the lock while raising into another thread's turn would be holding it
    # against that turn's own `exit`.
    # @param [String, Integer, LLM::Agent, Object] agent
    #  An id, an agent, or a record
    # @return [LLM::Agent, nil]
    def find(agent)
      @mutex.synchronize { @agents[key(agent)] }
    end

    private

    ##
    # The identity a cancel names.
    #
    # The record's id when the agent was built around one, because that is
    # what a host already has - a row it can name from a route - and the
    # agent's own otherwise.
    #
    # Asked as a question rather than as a class, and that is the whole of
    # this method. A host reaches it with whatever it holds: an agent, a
    # record, or an id. `LLM::Agent === agent` would answer "no" for the
    # record, whose id is what the caller has and what the turn registered
    # under - so the record's id is asked about, and a record is a thing
    # that has an id of its own rather than an agent at all.
    # @param [String, Integer, LLM::Agent, Object] agent
    # @return [String, Integer]
    def key(agent)
      case agent
      when String, Integer then agent
      else
        record = agent.record if agent.respond_to?(:record)
        record&.id || agent.id
      end
    end
  end
end
