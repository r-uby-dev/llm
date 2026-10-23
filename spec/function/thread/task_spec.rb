# frozen_string_literal: true

require "setup"
require "timeout"

RSpec.describe LLM::Function::Thread::Task do
  let(:gate) { Queue.new }
  let(:log) { Queue.new }
  let(:started) { Queue.new }
  let(:cleaned) { Queue.new }

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

  def settle(queue, timeout = 5)
    Timeout.timeout(timeout) { queue.pop }
  end

  def within(timeout = 5, &block)
    Timeout.timeout(timeout, &block)
  end

  describe "a cancel that arrives before the call runs" do
    before { task.interrupt! }

    it "is held rather than dropped" do
      expect(within { task.wait }).to be_a(LLM::Interrupt)
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
        expect(within { task.wait }).to be_a(LLM::Interrupt)
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
      settle(started)
      task.interrupt!
    end

    it "raises at the tool" do
      expect(within { task.wait }).to be_a(LLM::Interrupt)
    end

    it "runs the hook once the call has ended" do
      begin
        within { task.wait }
      rescue LLM::Interrupt
        nil
      end
      expect(log.size).to eq(1)
    end

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

  describe "a cancel that arrives once the thread has started" do
    before { task.spawn }

    it "does not hold the canceller" do
      expect(within { task.interrupt! }).to be_nil
    end

    it "interrupts the call" do
      task.interrupt!
      expect(within { task.wait }).to be_a(LLM::Interrupt)
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
      expect(within { task.wait }).to be_a(LLM::Interrupt)
    end
  end

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
