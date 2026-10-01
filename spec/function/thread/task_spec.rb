# frozen_string_literal: true

require "setup"
require "timeout"

##
# The four moments a cancel can arrive in, for a thread.
#
# A cancel is held before the call runs, raised while it runs, and a no-op
# once it has returned - and the first of those is the one that was missing:
# `interrupt!` had nothing to raise on before `spawn`, so an early cancel was
# dropped, `@delivered` was never set, the hook never ran, and the tool ran
# as if nobody had asked it to stop.
#
# **Every wait has a deadline.** The tool says when the call is live, and
# every wait for the call is wrapped, so a cancel that silently fails to be
# delivered is a failure that names itself rather than a cell that hangs.
#
# **The hook is counted rather than waited on.** It runs on the thread that
# ran the call, in that thread's `ensure`, so it has run by the time `#wait`
# has returned however the call ended - which means a queue can be read for
# its size instead of popped, and nothing waits for it at all.
#
# **The held cancel is spent by the body, and that is what this pins.** The
# first attempt at this raised a held cancel in from outside, and the run
# that followed showed what that costs: the interrupt was delivered, the
# thread ended with it, the caller was given it - and the hook never ran,
# because a raise into a thread that has not started can be delivered before
# the block's `ensure` is active. The call itself is still not entered, and
# no example asserts it: what a caller can depend on is the cancel taking
# effect, the hook running, and `#wait` raising.
RSpec.describe LLM::Function::Thread::Task do
  let(:gate) { Queue.new }
  let(:log) { Queue.new }
  let(:started) { Queue.new }

  ##
  # A tool that says it has started, then holds until the example lets it go,
  # and counts the interrupt it was told about.
  let(:holding) do
    started, gate, log = self.started, self.gate, self.log
    Class.new(LLM::Tool) do
      name "holding"
      define_method(:call) do
        started << :in_call
        gate.pop
        {ok: true}
      end
      define_method(:on_interrupt) do
        log << :interrupted
      end
    end
  end

  let(:fn) do
    holding.function.dup.tap do |fn|
      fn.id = "call_1"
      fn.arguments = {}
    end
  end

  let(:task) { fn.task(:thread) }

  ##
  # A queue read that cannot wait forever.
  def settle(queue, timeout = 5)
    Timeout.timeout(timeout) { queue.pop }
  end

  ##
  # And the same for anything else that might not come back.
  def within(timeout = 5, &block)
    Timeout.timeout(timeout, &block)
  end

  describe "a cancel that arrives before the call runs" do
    before do
      task.interrupt!
      ##
      # Opened so that a cancel which was dropped shows up as a return
      # rather than as a call that never ends.
      gate << true
    end

    it "is held rather than dropped" do
      expect { within { task.wait } }.to raise_error(LLM::Interrupt)
    end

    it "runs the hook once the call has ended" do
      begin
        within { task.wait }
      rescue LLM::Interrupt
        nil
      end
      expect(log.size).to eq(1)
    end

    it "has spawned nothing yet" do
      expect(task.alive?).to be(false)
    end
  end

  describe "a cancel that arrives while the call runs" do
    before do
      task.spawn
      ##
      # The tool says when it is live, so the cancel is raised at a call
      # rather than at its edge.
      settle(started)
      task.interrupt!
    end

    it "raises at the tool" do
      expect { within { task.wait } }.to raise_error(LLM::Interrupt)
    end

    it "runs the hook once the call has ended" do
      begin
        within { task.wait }
      rescue LLM::Interrupt
        nil
      end
      expect(log.size).to eq(1)
    end
  end

  describe "a cancel that arrives after the call has returned" do
    before do
      gate << true
      within { task.wait }
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
      expect(log).to be_empty
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
      expect { within { task.wait } }.to raise_error(LLM::Interrupt)
    end
  end

  ##
  # A group cancels its tasks in turn, and a task that has not been spawned
  # is one of them: the record is what makes that reach it, and nothing
  # pinned it.
  describe "a cancel for a group whose tasks have not been spawned" do
    let(:group) { LLM::Function::Thread::Group.new([task]) }

    before do
      group.interrupt!
      gate << true
    end

    it "reaches the task" do
      expect { within { group.wait } }.to raise_error(LLM::Interrupt)
    end

    it "runs the task's hook" do
      begin
        within { group.wait }
      rescue LLM::Interrupt
        nil
      end
      expect(log.size).to eq(1)
    end
  end
end
