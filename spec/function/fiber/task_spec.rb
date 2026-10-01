# frozen_string_literal: true

require "setup"
require "async"

##
# The four moments a cancel can arrive in, for a fiber.
#
# `interrupt!` was guarded by `@fiber&.alive?`, so a cancel that arrived
# before `spawn` - when there is no fiber to raise on - was dropped and the
# tool ran as if nothing had happened. The examples run inside a reactor
# because Ruby ships no default `Fiber.scheduler`, and `Async` is what
# installs the only kind there is.
RSpec.describe LLM::Function::Fiber::Task do
  let(:log) { Queue.new }
  let(:notification) { Async::Notification.new }

  ##
  # A tool that holds at a notification the example never sends, and counts
  # the interrupt it was told about. A notification yields to the scheduler,
  # which is what parks the call rather than blocking the thread.
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
  # A tool that answers at once, so the call has returned before the cancel
  # arrives.
  let(:quick) do
    Class.new(LLM::Tool) do
      name "quick"
      def call
        {ok: true}
      end
    end
  end

  def task_for(tool)
    tool.function.dup.tap do |fn|
      fn.id = "call_1"
      fn.arguments = {}
    end.task(:fiber)
  end

  ##
  # Runs the block inside a reactor and answers with the exception it ended
  # with. Expectations are made on what this returns rather than inside the
  # block, because a raise under `Async` is logged and never reaches RSpec - so
  # an example that asserts in there can pass having measured nothing.
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

  describe "a cancel that arrives before the call runs" do
    it "is held rather than dropped" do
      task = task_for(holding)
      task.interrupt!
      error = react { task.wait }
      expect(error).to be_a(LLM::Interrupt)
    end

    it "runs the hook once the call has ended" do
      task = task_for(holding)
      task.interrupt!
      error = react { task.wait }
      expect([error.class, log.size]).to eq([LLM::Interrupt, 1])
    end
  end

  describe "a cancel that arrives while the call runs" do
    it "raises at the tool" do
      task = task_for(holding)
      error = react do
        task.spawn
        task.interrupt!
        ##
        # The reactor's turn: the scheduler delivers the raise when this
        # thread lets it, and a read before that would block the thread the
        # reactor runs on.
        sleep 0.1
        task.wait
      end
      expect(error).to be_a(LLM::Interrupt)
    end
  end

  describe "a cancel that arrives after the call has returned" do
    it "is a no-op" do
      task = task_for(quick)
      cancelled = :unset
      error = react do
        task.wait
        cancelled = task.interrupt!
      end
      expect([error, cancelled]).to eq([nil, nil])
    end

    ##
    # The second wait is answered from what the first one took, which is what
    # `Thread#value` does for the other in-process strategy.
    it "preserves the result" do
      task = task_for(quick)
      first = second = nil
      error = react do
        first = task.wait
        task.interrupt!
        second = task.wait
      end
      expect([error, second.equal?(first)]).to eq([nil, true])
    end

    it "does not run the hook" do
      task = task_for(quick)
      error = react { task.wait }
      task.interrupt!
      expect([error, log.size]).to eq([nil, 0])
    end
  end

  ##
  # A group cancels its tasks in turn, and a task that has not been spawned is
  # one of them; the group's file has the rest of that story.
  describe "a cancel for a group whose tasks have not been spawned" do
    it "reaches the task" do
      task = task_for(holding)
      group = LLM::Function::Fiber::Group.new([task])
      group.interrupt!
      error = react { group.wait }
      expect(error).to be_a(LLM::Interrupt)
    end
  end
end
