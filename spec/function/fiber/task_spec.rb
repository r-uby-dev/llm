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
# **A fiber is entered where a thread may not be.** `Fiber.schedule` runs its
# block before it returns, so by the time `spawn` delivers a held cancel the
# call has started and is parked at the notification this file never sends -
# which is why the raise lands in the tool rather than at its edge, and why
# this file can assert the hook while the thread's file cannot assert the
# entry.
#
# **The reactor is what the strategy needs, and the timeout is what the
# example needs.** The strategy requires a `Fiber.scheduler`, and `Async`
# installs one on the thread its block runs on. Every wait for the call is
# wrapped in `Async::Task#with_timeout`, so a cancel that fails to be
# delivered is a failure that names itself rather than a cell that hangs.
#
# **The hook is counted rather than waited on**: it runs in the fiber's
# `ensure`, so it has run by the time `#wait` has returned however the call
# ended.
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

  describe "a cancel that arrives before the call runs" do
    it "is held rather than dropped" do
      task = task_for(holding)
      task.interrupt!
      Async do |root|
        root.with_timeout(5) do
          expect { task.wait }.to raise_error(LLM::Interrupt)
        end
      end
    end

    it "runs the hook once the call has ended" do
      task = task_for(holding)
      task.interrupt!
      Async do |root|
        root.with_timeout(5) do
          begin
            task.wait
          rescue LLM::Interrupt
            nil
          end
        end
      end
      expect(log.size).to eq(1)
    end
  end

  describe "a cancel that arrives while the call runs" do
    it "raises at the tool" do
      task = task_for(holding)
      Async do |root|
        root.with_timeout(5) do
          task.spawn
          task.interrupt!
          expect { task.wait }.to raise_error(LLM::Interrupt)
        end
      end
    end
  end

  describe "a cancel that arrives after the call has returned" do
    it "is a no-op" do
      task = task_for(quick)
      Async do |root|
        root.with_timeout(5) do
          task.wait
          expect(task.interrupt!).to be_nil
        end
      end
    end

    it "preserves the result" do
      task = task_for(quick)
      Async do |root|
        root.with_timeout(5) do
          result = task.wait
          task.interrupt!
          expect(task.wait).to equal(result)
        end
      end
    end

    it "does not run the hook" do
      task = task_for(quick)
      Async do |root|
        root.with_timeout(5) { task.wait }
      end
      task.interrupt!
      expect(log).to be_empty
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
      Async do |root|
        root.with_timeout(5) do
          expect { group.wait }.to raise_error(LLM::Interrupt)
        end
      end
    end
  end
end
