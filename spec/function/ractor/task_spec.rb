# frozen_string_literal: true

require "setup"

##
# Where a wait's answer comes from.
#
# A ractor answers one round trip and goes with the answering of it, so
# `Mailbox#wait` is not a request a terminated ractor can be asked. The
# task's own ractor is not asked for the result at all: the job hands the
# result to a ractor of the task's own before that ractor ends, and the
# wait takes it from there, whether it arrives before or after the task's
# ractor has gone. A wait after the first is answered from memory, the way
# `LLM::Function::Thread::Task#wait` answers from the thread's value.
#
# **A cancel that arrives while the tool is running is held, not dropped**:
# the job's watcher waits on the window the job opens immediately before the
# call, so a cancel that arrives first is delivered inside the call and the
# tool's own `rescue` sees it. The record of what reached the tool is the
# value the job sends back, because a ractor's copy of a tool is not the
# object the caller holds.
#
# **What the caller is given is this strategy's own answer**: a cancel that
# escapes the tool is a return with `cancelled: true`, not a raise out of
# `#wait`, which is the difference from `:fork` and is worth pinning beside
# it.
#
# **Every wait has a deadline.** A raise cannot be relied on to interrupt
# a wait on a ractor, so each of them runs on a thread of its own and is
# joined with a timeout: a round trip that does not come back is what
# this is about, and an example for it has to fail rather than hang.
RSpec.describe LLM::Function::Ractor::Task do
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
    thread = Thread.new(&block)
    thread.join(seconds) ? thread.value : raise("timed out after #{seconds} seconds")
  end

  ##
  # A tool that returns at once, so that the task has a result and then a
  # reason to go.
  let(:task) do
    Class.new(LLM::Tool) do
      name "quick"

      def call
        {ok: true}
      end
    end.function.dup.tap do |fn|
      fn.id = "call_1"
      fn.arguments = {}
    end.task(:ractor)
  end

  describe "a task that has been waited on" do
    it "answers a second wait from the result it has" do
      first = within { task.wait }
      expect(within { task.wait }).to equal(first)
    end

    it "answers a second wait with what the first one had" do
      first = within { task.wait }
      expect(within { task.wait }.to_h).to eq(first.to_h)
    end

    it "answers alive? from the result it has" do
      within { task.wait }
      expect(within { task.alive? }).to be(false)
    end
  end

  describe "a wait that arrives after the result is in" do
    it "is answered by the ractor the result was delivered to" do
      task.spawn
      ##
      # The tool is quick and the wait is late: by the time it comes, the
      # task's own ractor has answered the round trip it was there for
      # and gone with it. Before this change the wait went to that ractor,
      # and what came back was the refusal `Ractor#send` gives a port that
      # has closed - or, the race's other outcome, a wait that never came
      # back at all.
      sleep 0.05
      expect(within { task.wait }.to_h).to eq(
        id: "call_1", name: "quick", value: {ok: true}
      )
    end
  end

  ##
  # The task's own ractor has gone by the time the cancel comes, which is
  # what a caller finds after a result has been delivered: the cancel is a
  # no-op rather than a `::Ractor::ClosedError` on its thread.
  describe "a task that has returned" do
    it "answers a cancel with nil rather than a raise" do
      within { task.wait }
      expect(within { task.interrupt! }).to be_nil
    end
  end

  ##
  # A tool that records what reached it. The hook writes a flag and the rescue
  # reads it back, so one value says both that the rescue ran and that the hook
  # was written first - which is the order the job's watcher promises, and the
  # reason a tool that releases a resource has released it by the time the
  # raise lands.
  let(:recording_tool) do
    Class.new(LLM::Tool) do
      name "recording"

      def call
        @entered = true
        sleep 5
        {ok: true}
      rescue LLM::Interrupt
        {entered: @entered, told: @told, rescued: true}
      end

      def on_interrupt
        @told = true
      end
    end
  end

  ##
  # A tool that holds and does not rescue, so the interrupt escapes it and the
  # job answers the cancel its own way.
  let(:holding_tool) do
    Class.new(LLM::Tool) do
      name "holding"

      def call
        sleep 5
        {ok: true}
      end
    end
  end

  ##
  # The cancel follows `spawn` by as little as the file can say, so the ractor
  # is still starting when the message is written: the watcher waits on a
  # window that is still idle, and the tool is entered before the raise lands.
  describe "a call that was cancelled while the tool was starting" do
    let(:task) do
      recording_tool.function.dup.tap do |fn|
        fn.id = "call_2"
        fn.arguments = {}
      end.task(:ractor)
    end
    let(:returned) { within { task.wait } }

    before do
      task.spawn
      task.interrupt!
      returned
    end

    it "enters the tool" do
      expect(returned.value[:entered]).to be(true)
    end

    it "runs the tool's own rescue" do
      expect(returned.value[:rescued]).to be(true)
    end

    it "tells the tool before the raise lands" do
      expect(returned.value[:told]).to be(true)
    end
  end

  ##
  # And the same cancel on a call that does not rescue: the interrupt escapes
  # the tool, and the job answers it as this strategy answers a cancel - a
  # return with `cancelled: true`, rather than a raise out of `#wait`.
  describe "a call cancelled while the tool was starting that does not rescue" do
    let(:task) do
      holding_tool.function.dup.tap do |fn|
        fn.id = "call_3"
        fn.arguments = {}
      end.task(:ractor)
    end
    let(:returned) { within { task.wait } }

    before do
      task.spawn
      task.interrupt!
    end

    it "answers with a cancelled return rather than raising" do
      expect(returned.to_h).to eq(
        id: "call_3", name: "holding",
        value: {cancelled: true, reason: "interrupted"}
      )
    end
  end
end
