# frozen_string_literal: true

require "setup"

##
# A cancel for a group of calls, one of which has already returned.
#
# `Group#interrupt!` maps over its tasks in order, and a task whose ractor
# has gone raises `::Ractor::ClosedError` from the mailbox it cancels
# through. One finished call therefore stopped the cancel at that call,
# and every call after it kept running - which is the opposite of what a
# group interrupt is for.
#
# **Every wait has a deadline.** A raise cannot be relied on to interrupt
# a wait on a ractor, so each of them runs on a thread of its own and is
# joined with a timeout: a round trip that does not come back is what this
# is about, and an example for it has to fail rather than hang.
RSpec.describe LLM::Function::Ractor::Group do
  ##
  # The ractor's examples are not supported by yajl or oj, and the matrix
  # spells the cell that supports them `JSON`, so the parser is compared
  # as it is written.
  before do
    skip "not supported by yajl or oj" unless ENV.fetch("JSON_PARSER", "json").downcase == "json"
  end

  ##
  # Runs the block on a thread of its own and joins it, so a wait that
  # never comes back is a failure that names the wait rather than a hang.
  def within(seconds = 5, &block)
    thread = Thread.new do
      ##
      # The block is expected to raise: a cancelled call is raised on the
      # caller now, rather than answered with it, so a thread's own report
      # of the exception would be noise.
      Thread.current.report_on_exception = false
      block.call
    end
    thread.join(seconds) ? thread.value : raise("timed out after #{seconds} seconds")
  end

  ##
  # The returned call is first, because the cancel is what used to stop at
  # it: a task whose ractor has gone is where the map raised.
  let(:group) { LLM::Function::Ractor::Group.new([finished, holding]) }

  ##
  # A call that has returned, so that its ractor has gone by the time the
  # cancel reaches it.
  let(:finished) do
    Class.new(LLM::Tool) do
      name "finished"

      def call
        {ok: true}
      end
    end.function.dup.tap do |fn|
      fn.id = "call_1"
      fn.arguments = {}
    end.task(:ractor)
  end

  ##
  # A call that holds, so that the cancel has something to interrupt.
  let(:holding) do
    Class.new(LLM::Tool) do
      name "holding"

      def call
        sleep 2
        {ok: true}
      end
    end.function.dup.tap do |fn|
      fn.id = "call_2"
      fn.arguments = {}
    end.task(:ractor)
  end

  describe "a cancel for a group with a returned call in it" do
    before do
      group.spawn
      within { finished.wait }
      group.interrupt!
    end

    it "reaches the calls after the one that has returned" do
      expect { within { group.wait } }.to raise_error(LLM::Interrupt)
    end
  end
end
