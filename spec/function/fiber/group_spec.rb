# frozen_string_literal: true

require "setup"
require "async"

##
# A group of fiber calls, and what a cancel does to one.
#
# The group is the other half of the strategy the task's file covers. It
# spawns its tasks in turn and waits on each of them, so a cancel has to
# reach a task that has not been spawned, and it has to keep going past one
# that has already returned - both of which the task's record makes work,
# and neither of which anything pinned before this file.
#
# **The scheduler is `Async`'s, because it has to be somebody's.** Ruby
# ships no default `Fiber.scheduler`, so a strategy that runs its call with
# `Fiber.schedule` leans on something the runtime does not provide: a
# scheduler has to be installed, and the thread it is installed on is the
# thread whose work is cooperative from then on. `Async` installs one for its
# block, and that is the one here - not a stand-in for a scheduler Ruby would
# have given us, but the only kind that exists.
#
# **The reactor is a thread, and a wait blocks it.** `Queue#pop` is not the
# scheduler's, so an example that waits inside the reactor stops the thread
# the reactor runs on - and the interrupt the scheduler was asked to deliver
# waits with it. Where an example has a parked call to interrupt, it gives
# the reactor a turn first and then reads.
#
# **Every answer is taken out of the reactor and asserted here.** An
# exception inside `Async do |root| ... end` never reaches RSpec: the top
# level `Async` returns the initial task rather than waiting on it, so a raise
# is logged and the example ends green having measured nothing.
RSpec.describe LLM::Function::Fiber::Group do
  let(:log) { Queue.new }
  let(:notification) { Async::Notification.new }

  ##
  # A tool that holds at a notification the example never sends, and counts
  # the interrupt it was told about, so a parked call is something a cancel
  # can reach and something the example can see it reached.
  let(:holding) do
    notification, log = self.notification, self.log
    Class.new(LLM::Tool) do
      name "holding"
      define_method(:call) do
        notification.wait
        {ok: true}
      end
      define_method(:on_interrupt) do
        log << :interrupted
      end
    end
  end

  ##
  # And one that answers at once, so a group can hold a call that has already
  # returned beside one that has not.
  let(:quick) do
    Class.new(LLM::Tool) do
      name "quick"
      def call
        {ok: true}
      end
    end
  end

  def task_for(tool, id)
    tool.function.dup.tap do |fn|
      fn.id = id
      fn.arguments = {}
    end.task(:fiber)
  end

  def react(timeout = 5, &block)
    error = nil
    Async do |root|
      root.with_timeout(timeout) do
        block.call
      rescue => ex
        error = ex
      end
    end
    error
  end

  ##
  # The happy path, which is what a group is for: every task spawned, and a
  # return for each of them in the order they were given.
  describe "a group of calls that answer" do
    it "answers with a return for each of them" do
      group = described_class.new([task_for(quick, "call_1"), task_for(quick, "call_2")])
      returns = nil
      error = react { returns = group.wait }
      expect([error, returns.map(&:id)]).to eq([nil, %w[call_1 call_2]])
    end
  end

  ##
  # A cancel before the group is spawned reaches the tasks anyway, because
  # the record is per task and the group's `interrupt!` is a map over them.
  describe "a cancel before the group is spawned" do
    it "reaches a task that has not started" do
      group = described_class.new([task_for(holding, "call_1")])
      group.interrupt!
      error = react { group.wait }
      expect(error).to be_a(LLM::Interrupt)
    end
  end

  ##
  # The returned call is first, because the cancel is what used to stop at
  # it: the tasks after it are the ones a group's map has to keep reaching.
  describe "a cancel for a group with a returned call in it" do
    it "reaches the calls after the one that has returned" do
      group = described_class.new([task_for(quick, "call_1"), task_for(holding, "call_2")])
      error = react do
        group.spawn
        group.value.tap { nil }
        group.interrupt!
        ##
        # The reactor's turn: the scheduler is asked to raise on the parked
        # call, and it delivers when this thread lets it.
        sleep 0.1
      end
      expect([error, log.size]).to eq([nil, 1])
    end
  end
end
