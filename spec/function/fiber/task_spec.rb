# frozen_string_literal: true

require "setup"
require "async"

##
# The four moments a cancel can arrive in, for a fiber.
#
# This is the thread strategy's defect one strategy over: `interrupt!` was
# guarded by `@fiber&.alive?`, and before `spawn` there is no fiber - so an
# early cancel was dropped, `@delivered` was never set, the hook never ran,
# and the tool ran as if nothing had happened.
#
# **A fiber is entered where a thread may not be.** `Fiber.schedule` runs its
# block before it returns, so by the time `spawn` can deliver a held cancel
# the call has started and is suspended inside itself: the raise lands at a
# yield point inside the tool, and the tool's own rescue and ensure run. A
# thread has no such guarantee, which is why that file asserts the hook and
# this one can also assert the call.
#
# **The scheduler is the reactor's.** `Fiber.schedule` requires a
# `Fiber.scheduler`, and `Async` installs one for the block it runs, so each
# example runs its waits inside one. The holding call sleeps, which is what
# yields to that scheduler.
RSpec.describe LLM::Function::Fiber::Task do
  let(:log) { Queue.new }

  ##
  # A tool that holds by sleeping - the one wait a scheduler-backed fiber
  # can take without blocking the thread the reactor runs on - and records
  # the interrupt it was told about.
  let(:holding) do
    log = self.log
    Class.new(LLM::Tool) do
      name "holding"
      define_method(:call) do
        sleep 5
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
      Async do
        expect { task.wait }.to raise_error(LLM::Interrupt)
      end
    end

    it "runs the hook once the call has ended" do
      task = task_for(holding)
      task.interrupt!
      Async do
        task.wait
      rescue LLM::Interrupt
        nil
      end
      expect(log.pop).to eq(:interrupted)
    end

    ##
    # A tool that answers at once cannot be interrupted after the fact, and
    # the cancel that arrives with it is the no-op the contract asks for -
    # the call has returned, and a return is what the caller is given.
    it "leaves a call that has already returned alone" do
      task = task_for(quick)
      Async do
        expect(task.wait.to_h).to eq(id: "call_1", name: "quick", value: {ok: true})
      end
    end
  end

  describe "a cancel that arrives while the call runs" do
    it "raises at the tool" do
      task = task_for(holding)
      Async do
        task.spawn
        task.interrupt!
        expect { task.wait }.to raise_error(LLM::Interrupt)
      end
    end
  end

  describe "a cancel that arrives after the call has returned" do
    it "is a no-op" do
      task = task_for(quick)
      Async do
        task.wait
        expect(task.interrupt!).to be_nil
      end
    end

    it "preserves the result" do
      task = task_for(quick)
      Async do
        result = task.wait
        task.interrupt!
        expect(task.wait).to equal(result)
      end
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
      Async do
        expect { group.wait }.to raise_error(LLM::Interrupt)
      end
    end
  end
end
