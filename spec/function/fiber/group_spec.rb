# frozen_string_literal: true

require "setup"
require "async"

##
# A group of fiber calls, and what a cancel does to one.
#
# The group spawns its tasks in turn and waits on each, so a cancel has to
# reach a task that has not been spawned, and a wait has to be served for a
# call that is still parked. The examples run inside a reactor because Ruby
# ships no default `Fiber.scheduler`, and `Async` installs the only kind there
# is.
RSpec.describe LLM::Function::Fiber::Group do
  let(:log) { Queue.new }
  let(:notification) { Async::Notification.new }

  ##
  # A tool that holds at a notification, and counts the interrupt it was told
  # about - so a parked call is something a cancel can reach, and something
  # the example can see it reached.
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

  ##
  # Runs the block inside a reactor and answers with the exception it ended
  # with. Expectations are made on what this returns rather than inside the
  # block, because a raise under `Async` is logged and never reaches RSpec.
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
  # A group waits on its tasks in turn, so the first wait is for a call that
  # has not answered yet. The reactor serves it - the pop parks the fiber, the
  # parked call runs to its end, and the push wakes the waiter - which is the
  # case the group's handoff was built for and the one no example reached.
  describe "a group with a call that is parked" do
    it "answers with a return for each of them" do
      parked = task_for(holding, "call_1")
      answered = task_for(quick, "call_2")
      returns = nil
      error = react do
        group = described_class.new([parked, answered])
        group.spawn
        notification.signal
        returns = group.wait.map(&:id)
      end
      expect([error, returns]).to eq([nil, %w[call_1 call_2]])
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
  # The returned call is first, because the cancel is what used to stop at it:
  # the calls after it are the ones the map has to keep reaching. What is
  # asserted is the hook, not a return - the parked call stays parked here.
  describe "a cancel for a group with a returned call in it" do
    it "reaches the calls after the one that has returned" do
      finished = task_for(quick, "call_1")
      parked = task_for(holding, "call_2")
      group = described_class.new([finished, parked])
      error = react do
        group.spawn
        ##
        # A read, not a wait: the block already filled the queue.
        finished.wait
        group.interrupt!
        ##
        # The reactor's turn, so the scheduler can deliver the raise.
        sleep 0.1
      end
      expect([error, log.size]).to eq([nil, 1])
    end
  end
end
