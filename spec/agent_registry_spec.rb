# frozen_string_literal: true

require "setup"

##
# The registry, and the two ways a turn is named.
#
# The identity is what a host already has: a record's id when the agent was
# built around one, the agent's own otherwise. The examples are about those
# two spellings reaching one entry, about the agent itself being a spelling of
# its own, and about the edges - nothing registered, and a second turn under
# one identity.
RSpec.describe LLM::Agent::Registry do
  subject(:registry) { described_class.new }

  let(:row) { double(id: "a-row-id") }
  let(:agent) { double(record: row, id: "an-agent-id") }

  describe "an agent that is running" do
    before { registry.enter(agent) }

    it "is found by the agent" do
      expect(registry.find(agent:)).to equal(agent)
    end

    ##
    # The spelling a route has: it knows the row, not the object.
    it "is found by its record's id" do
      expect(registry.find(id: "a-row-id")).to equal(agent)
    end

    ##
    # One key, not two. An agent with a record answers to the record's id
    # and not also to its own - that is what `record&.id || id` decides.
    it "is not also found by its own id" do
      expect(registry.find(id: "an-agent-id")).to be_nil
    end
  end

  describe "an agent that was built around no record" do
    let(:agent) { double(record: nil, id: "an-agent-id") }

    before { registry.enter(agent) }

    it "is found by its own id" do
      expect(registry.find(id: "an-agent-id")).to equal(agent)
    end
  end

  describe "an agent whose turn is over" do
    before do
      registry.enter(agent)
      registry.exit(agent)
    end

    it "is not found" do
      expect(registry.find(agent:)).to be_nil
    end
  end

  describe "an agent that never registered" do
    it "is not found" do
      expect(registry.find(agent:)).to be_nil
    end
  end

  ##
  # Naming a turn by both, or by neither, is a mistake rather than a
  # question: there is one answer and two ways to ask for it.
  describe "naming a turn by nothing" do
    it "is refused" do
      expect { registry.find }.to raise_error(ArgumentError)
    end
  end

  describe "naming a turn by both" do
    it "is refused" do
      expect { registry.find(agent:, id: "a-row-id") }.to raise_error(ArgumentError)
    end
  end

  ##
  # Two turns under one identity is the case that decides the rule: the one
  # that finishes first is not necessarily the one that registered last.
  describe "a second agent registered under one identity" do
    let(:second) { double(record: double(id: "a-row-id"), id: "another-agent-id") }

    before do
      registry.enter(agent)
      registry.enter(second)
      registry.exit(agent)
    end

    it "is left alone by the first one's exit" do
      expect(registry.find(id: "a-row-id")).to equal(second)
    end
  end
end
