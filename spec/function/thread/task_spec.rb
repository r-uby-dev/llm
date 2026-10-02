# frozen_string_literal: true

require "setup"
require "timeout"

##
# The four moments a cancel can arrive in, for a thread.
#
# A cancel is held before the call runs, raised while it runs, and a no-op
# once it has returned; the first of those was dropped, because `interrupt!`
# had nothing to raise on before `spawn`. The held cancel is delivered inside
# the call now, so a tool whose own rescue cleans up is cleaned up - and every
# wait here has a deadline, a wrong expectation fails rather than hangs.
#
# The tools hold at the gate rather than running straight through, which is
# what makes a held cancel measurable: a tool that finished before the raise
# landed would be a call with nothing left to interrupt, and the example would
# be measuring the schedule rather than the delivery.
RSpec.describe LLM::Function::Thread::Task do
  let(:gate) { Queue.new }
  let(:log) { Queue.new }
  let(:started) { Queue.new }
  let(:cleaned) { Queue.new }

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

  ##
  # And one that cleans up in its own rescue and raises on, so the caller
  # still sees the interrupt - which is the whole of what the held cancel has
  # to reach: the tool's rescue, and the caller's exception.
  let(:rescuing) do
    started, gate, cleaned = self.started, self.gate, self.cleaned
    Class.new(LLM::Tool) do
      name "rescuing"
      define_method(:call) do
        started << :in_call
        gate.pop
        {ok: true}
      rescue LLM::Interrupt
        cleaned << :cleaned_up
        raise
      end
    end
  end

  ##
  # And one whose only notification is the hook under its other name.
  let(:cancelling) do
    started, gate, log = self.started, self.gate, self.log
    Class.new(LLM::Tool) do
      name "cancelling"
      define_method(:call) do
        started << :in_call
        gate.pop
        {ok: true}
      end
      define_method(:on_cancel) do
        log << :cancelled
      end
    end
  end

  def fn_for(tool)
    tool.function.dup.tap do |fn|
      fn.id = "call_1"
      fn.arguments = {}
    end
  end

  let(:fn) { fn_for(holding) }

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
    before { task.interrupt! }

    it "is held rather than dropped" do
      expect { within { task.wait } }.to raise_error(LLM::Interrupt)
    end

    ##
    # The hook is counted rather than waited on: it runs in the thread's
    # `ensure`, so it has run by the time `#wait` has returned.
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

    ##
    # The tool is entered, which is the whole of what this strategy was
    # missing: the cancel used to be raised before `function.call`, so a tool
    # that cleans up in its own rescue never ran its rescue.
    context "when the tool cleans up in its own rescue" do
      let(:fn) { fn_for(rescuing) }

      it "is entered and cleans up" do
        begin
          within { task.wait }
        rescue LLM::Interrupt
          nil
        end
        expect(cleaned.size).to eq(1)
      end

      it "still raises to the caller" do
        expect { within { task.wait } }.to raise_error(LLM::Interrupt)
      end
    end

    context "when the tool is told through on_cancel" do
      let(:fn) { fn_for(cancelling) }

      it "is told" do
        begin
          within { task.wait }
        rescue LLM::Interrupt
          nil
        end
        expect(settle(log)).to eq(:cancelled)
      end
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

    ##
    # And a running cancel reaches the tool's own rescue too, which is what
    # the held one now does as well.
    context "when the tool cleans up in its own rescue" do
      let(:fn) { fn_for(rescuing) }

      it "is cleaned up" do
        begin
          within { task.wait }
        rescue LLM::Interrupt
          nil
        end
        expect(cleaned.size).to eq(1)
      end
    end
  end

  ##
  # `#interrupt!` waits now - for the body to publish the window, and inside
  # the window for the call to open - and this is the case that wait is for.
  # The task is spawned and interrupted with nothing in between, so the window
  # is still idle when the canceller arrives: it waits there rather than
  # returning, and the tool holds at the gate, so the interrupt still lands
  # inside the call. A group and `Context#interrupt!` meet the same wait in a
  # loop, which is why the answer matters.
  describe "a cancel that arrives once the thread has started" do
    before { task.spawn }

    it "does not hold the canceller" do
      expect(within { task.interrupt! }).to be_nil
    end

    it "interrupts the call" do
      task.interrupt!
      expect { within { task.wait } }.to raise_error(LLM::Interrupt)
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

    before { task.interrupt! }

    it "is held rather than dropped" do
      expect { within { task.wait } }.to raise_error(LLM::Interrupt)
    end
  end

  ##
  # A group cancels its tasks in turn, and a task that has not been spawned
  # is one of them: the record is what makes that reach it.
  describe "a cancel for a group whose tasks have not been spawned" do
    let(:group) { LLM::Function::Thread::Group.new([task]) }

    before { group.interrupt! }

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
