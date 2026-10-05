# frozen_string_literal: true

require "setup"

##
# The registry, and the two things it promises.
#
# The identity is what a host already has, and the examples are about the two
# spellings reaching one entry: a record and the agent built around it are the
# same turn, and a cancel written against either finds it. The rest are the
# edges - nothing registered, and a second turn under one identity.
#
# An agent's own id is a spelling of its own, but not for an agent that has a
# record: the key is one value, `record&.id || id`, so an agent with a record
# answers to the record's id and not to both. That is the whole reason the key
# is written that way, and it is asserted below.
RSpec.describe LLM::Agent::Registry do
  subject(:registry) { described_class.new }

  ##
  # An agent's two identities, and the record it may have been built around.
  let(:row) { double(id: "a-row-id") }
  let(:agent) { double(record: row, id: "an-agent-id") }

  describe "an agent that is running" do
    before { registry.enter(agent) }

    it "is found by the agent" do
      expect(registry.find(agent)).to equal(agent)
    end

    ##
    # The spelling a route has: it knows the row, not the object.
    it "is found by its record's id" do
      expect(registry.find("a-row-id")).to equal(agent)
    end

    it "is found by the record itself" do
      expect(registry.find(row)).to equal(agent)
    end

    ##
    # One key, not two. The agent's own id names it only when there is no
    # record to name it by, which is what `record&.id || id` decides.
    it "is not also found by its own id" do
      expect(registry.find("an-agent-id")).to be_nil
    end
  end

  describe "an agent that was built around no record" do
    let(:agent) { double(record: nil, id: "an-agent-id") }

    before { registry.enter(agent) }

    it "is found by its own id" do
      expect(registry.find("an-agent-id")).to equal(agent)
    end
  end

  describe "an agent whose turn is over" do
    before do
      registry.enter(agent)
      registry.exit(agent)
    end

    it "is not found" do
      expect(registry.find("a-row-id")).to be_nil
    end
  end

  describe "an agent that never registered" do
    it "is not found" do
      expect(registry.find("a-row-id")).to be_nil
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
      expect(registry.find("a-row-id")).to equal(second)
    end
  end
end
