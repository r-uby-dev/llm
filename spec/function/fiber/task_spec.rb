# frozen_string_literal: true

require "setup"
require "async"

##
# The four moments a cancel can arrive in, for a fiber.
#
# This is the thread strategy's defect one strategy over: `interrupt!` was
# guarded by `@fiber&.alive?`, and before `spawn` there is no fiber, so an
# early cancel was dropped, `@delivered` was never set, the hook never ran,
# and the tool ran as if nothing had happened.
#
# **Every example takes its answer out of the reactor and asserts it here.**
# An exception inside `Async do |root| ... end` does not reach RSpec: the top
# level `Async` runs `Async::Reactor#run`, which returns the initial task
# rather than waiting on it, so a raise inside the block is logged as "Task
# may have ended with unhandled exception" and the example ends green having
# evaluated no assertion at all. That is a trap, and three of these examples
# fell into it before a review said so: the reactor's work is wrapped, the
# error is carried out in a local, and the expectation is made out here,
# where it can fail.
#
# **A held cancel is spent by the body.** A raise into a fiber a scheduler
# owns does not deliver - the first run of this file saw the scheduler's own
# `Async::TimeoutError` arrive where `LLM::Interrupt` was raised - so the
# block raises at its first instruction, where the scheduler is not in the
# way and the hook below it is active.
#
# **The running cancel is the scheduler's raise.** `interrupt!` asks the
# scheduler to interrupt the fiber, because raising directly suspends the
# thread it is called on - which is the caller's thread, so the interrupt
# reaches the tool and the canceller never comes back.
RSpec.describe LLM::Function::Fiber::Task do
  let(:log) { Queue.new }
  let(:notification) { Async::Notification.new }

  ##
  # A tool that holds at a notification the example never sends, and counts
  # the interrupt it was told about. A notification yields to the scheduler,
  # which is what parks the call inside the reactor rather than blocking the
  # thread the reactor runs on.
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
  # A tool that answers at once, so that the call has returned before the
  # cancel arrives.
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
  # with, if it ended with one. The reactor stops when the block returns, so
  # nothing is left running behind the example.
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
    # `Thread#value` does and what the ractor's task is expected to do.
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
  # A group cancels its tasks in turn, and a task that has not been spawned
  # is one of them.
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
