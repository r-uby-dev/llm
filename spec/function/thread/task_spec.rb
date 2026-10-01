# frozen_string_literal: true

require "setup"

##
# The four moments a cancel can arrive in, for a thread.
#
# A cancel is held before the call runs, raised while it runs, and a no-op
# once it has returned. The first of those is the one that was missing:
# `interrupt!` had nothing to raise on before `spawn`, so a cancel that
# arrived early was dropped, `@delivered` was never set, the hook never ran,
# and the tool ran as if nobody had asked it to stop.
#
# **The hook is what says a cancel took effect.** It runs on the thread that
# ran the call, once the call has ended, and only for a cancel that was
# raised into a live thread - so it is the difference between a cancel that
# was received and one that did something.
#
# **The thread's own entry is not asserted.** A raise into a thread that has
# not started is delivered at its first checkpoint, which is at or just
# inside the call, and which of the two it is depends on the schedule the
# two threads reach their next instruction in. What the caller can depend on
# is what these examples assert: the cancel is not dropped, the hook runs,
# and `#wait` raises.
#
# **Nothing is timed by a clock.** A tool that holds is held by a queue the
# example fills, so an example says when the call is live rather than waiting
# to find out, and a cancel that did nothing fails rather than hangs.
RSpec.describe LLM::Function::Thread::Task do
  let(:gate) { Queue.new }
  let(:log) { Queue.new }
  let(:started) { Queue.new }

  ##
  # A tool that says it has started, then holds until the example lets it
  # go, and records the interrupt it was told about.
  let(:holding) do
    started, gate, log = self.started, self.gate, self.log
    Class.new(LLM::Tool) do
      name "holding"
      define_method(:call) do
        started << true
        gate.pop
        {ok: true}
      end
      define_method(:on_interrupt) do
        log << :interrupted
      end
    end
  end

  let(:task) do
    holding.function.dup.tap do |fn|
      fn.id = "call_1"
      fn.arguments = {}
    end.task(:thread)
  end

  describe "a cancel that arrives before the call runs" do
    ##
    # The gate is opened so that a cancel which was dropped shows up as a
    # return rather than as a wait that never ends.
    before do
      task.interrupt!
      gate << true
    end

    it "is held rather than dropped" do
      expect { task.wait }.to raise_error(LLM::Interrupt)
    end

    it "runs the hook once the call has ended" do
      task.wait
    rescue LLM::Interrupt
      nil
    ensure
      expect(log.pop).to eq(:interrupted)
    end

    it "answers alive? with a thread it has not spawned yet" do
      expect(task.alive?).to be(false)
    end
  end

  describe "a cancel that arrives while the call runs" do
    before do
      task.spawn
      started.pop
      task.interrupt!
    end

    it "raises at the tool" do
      expect { task.wait }.to raise_error(LLM::Interrupt)
    end

    it "runs the hook once the call has ended" do
      task.wait
    rescue LLM::Interrupt
      nil
    ensure
      expect(log.pop).to eq(:interrupted)
    end
  end

  describe "a cancel that arrives after the call has returned" do
    before do
      gate << true
      task.wait
    end

    it "is a no-op" do
      expect(task.interrupt!).to be_nil
    end

    it "preserves the result" do
      result = task.wait
      task.interrupt!
      expect(task.wait).to equal(result)
    end

    it "does not run the hook" do
      task.interrupt!
      expect(log.pop(true) { :none }).to eq(:none)
    end
  end

  ##
  # A function that is not a tool class has no hook to tell, and is
  # interrupted the same way otherwise.
  describe "a cancel for a function that is not a tool class" do
    let(:task) do
      LLM::Function.new("block").tap do |fn|
        fn.define do
          gate.pop
          {ok: true}
        end
        fn.id = "call_2"
        fn.arguments = {}
      end.task(:thread)
    end

    before do
      task.interrupt!
      gate << true
    end

    it "is held rather than dropped" do
      expect { task.wait }.to raise_error(LLM::Interrupt)
    end
  end

  ##
  # A group cancels its tasks in turn, and a task that has not been spawned
  # is one of them: the record is what makes that work, and nothing pinned
  # it.
  describe "a cancel for a group whose tasks have not been spawned" do
    let(:group) { LLM::Function::Thread::Group.new([task]) }

    before do
      group.interrupt!
      gate << true
    end

    it "reaches the task" do
      expect { group.wait }.to raise_error(LLM::Interrupt)
    end
  end
end
