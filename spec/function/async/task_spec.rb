# frozen_string_literal: true

require "setup"
require "timeout"

RSpec.describe LLM::Function::Async::Task do
  let(:started) { Queue.new }
  let(:finished) { Queue.new }
  let(:cleaned) { Queue.new }
  let(:told) { Queue.new }
  let(:reactor) { LLM::Function::Async::Reactor.new }
  after { reactor.stop }

  let(:counting) do
    started, finished = self.started, self.finished
    Class.new(LLM::Tool) do
      name "counting"
      define_method(:call) do
        started << :in_call
        loop { sleep 0.01 }
      ensure
        finished << :done
      end
    end
  end

  let(:rescuing) do
    started = self.started
    Class.new(LLM::Tool) do
      name "rescuing"
      define_method(:call) do
        started << :in_call
        sleep 0.05
        {"ok" => true}
      rescue LLM::Interrupt
        sleep 0.05
        {"ok" => true, "interrupted" => true}
      end
    end
  end

  let(:cleaning) do
    started, cleaned = self.started, self.cleaned
    Class.new(LLM::Tool) do
      name "cleaning"
      define_method(:call) do
        started << :in_call
        loop { sleep 0.01 }
      rescue LLM::Interrupt
        cleaned << :cleaned_up
        raise
      end
    end
  end

  let(:cancelling) do
    started, told = self.started, self.told
    Class.new(LLM::Tool) do
      name "cancelling"
      define_method(:call) do
        started << :in_call
        loop { sleep 0.01 }
      end
      define_method(:on_cancel) do
        told << :cancelled
      end
    end
  end

  let(:quick) do
    started, told = self.started, self.told
    Class.new(LLM::Tool) do
      name "quick"
      define_method(:call) do
        started << :in_call
        {"ok" => true}
      end
      define_method(:on_interrupt) do
        told << :interrupted
      end
    end
  end

  let(:tool) { counting }

  let(:task) do
    tool.function.dup.tap do |fn|
      fn.id = "call_1"
      fn.arguments = {}
    end.task(:async).tap { |task| task.reactor = reactor }
  end

  def settle(queue, timeout = 5)
    Timeout.timeout(timeout) { queue.pop }
  end

  def within(timeout = 5, &block)
    Timeout.timeout(timeout, &block)
  end

  describe "a cancel that arrives before the call runs" do
    before do
      task.interrupt!
      task.spawn
    end

    it "enters the tool" do
      expect(settle(started)).to eq(:in_call)
    end

    it "raises LLM::Interrupt to the caller" do
      expect(within { task.wait }).to be_a(LLM::Interrupt)
    end

    context "when the tool cleans up in its own rescue" do
      let(:tool) { cleaning }

      it "is cleaned up" do
        expect(settle(cleaned)).to eq(:cleaned_up)
      end

      it "still raises to the caller" do
        expect(within { task.wait }).to be_a(LLM::Interrupt)
      end
    end

    context "when the tool is told through on_cancel" do
      let(:tool) { cancelling }

      it "is told" do
        expect(settle(told)).to eq(:cancelled)
      end
    end

    context "when the tool answers before anything can reach it" do
      let(:tool) { quick }

      it "answers with the tool's result" do
        expect(within { task.wait }.to_h[:value]).to eq("ok" => true)
      end

      it "tells the tool" do
        expect(settle(told)).to eq(:interrupted)
      end

      context "when another task is on the same reactor" do
        let(:sibling) do
          quick.function.dup.tap do |fn|
            fn.id = "call_2"
            fn.arguments = {}
          end.task(:async).tap { |task| task.reactor = reactor }
        end

        before do
          task.spawn
          sleep 0.05
          sibling.spawn
        end

        it "leaves the reactor usable" do
          expect(within { sibling.wait }.to_h[:value]).to eq("ok" => true)
        end
      end
    end
  end

  describe "a cancel that arrives after the block has started" do
    before do
      task.spawn
      task.interrupt!
    end

    it "enters the tool" do
      expect(settle(started)).to eq(:in_call)
    end

    it "raises LLM::Interrupt to the caller" do
      expect(within { task.wait }).to be_a(LLM::Interrupt)
    end
  end

  describe "a cancel for a task that never spawned" do
    it "is a no-op" do
      expect(task.interrupt!).to be_nil
    end
  end

  describe "a cancel that arrives while the call runs" do
    before do
      task.spawn
      settle(started)
      task.interrupt!
    end

    it "is told, and stops running" do
      expect(settle(finished)).to eq(:done)
    end

    it "raises LLM::Interrupt to the caller" do
      expect(within { task.wait }).to be_a(LLM::Interrupt)
    end

    context "once the caller has waited" do
      before do
        within { task.wait }
      rescue LLM::Interrupt
        nil
      end

      it "stops the reactor it ran on" do
        expect(reactor.thread).not_to be_alive
      end
    end
  end

  describe "a tool that handles the interrupt" do
    let(:tool) { rescuing }

    before do
      task.spawn
      settle(started)
      task.interrupt!
    end

    it "is let to, and answers with its own value" do
      expect(within { task.wait }.to_h[:value]).to eq("ok" => true, "interrupted" => true)
    end
  end

  describe "a cancel that arrives after the call has returned" do
    let(:tool) { rescuing }

    before { within { task.wait } }

    it "is a no-op" do
      expect(task.interrupt!).to be_nil
    end
  end

  describe "a task that has been waited on" do
    let(:tool) { rescuing }
    let(:first) { within { task.wait } }

    before { first }

    it "answers a second wait from the result it has" do
      expect(within { task.wait }).to equal(first)
    end

    it "answers a second wait with what the first one had" do
      expect(within { task.wait }.to_h).to eq(first.to_h)
    end
  end

  describe "a task whose call was interrupted" do
    let(:interrupted) do
      task.spawn
      settle(started)
      task.interrupt!
      within { task.wait }
      nil
    rescue LLM::Interrupt => ex
      ex
    end

    before { interrupted }

    it "raises LLM::Interrupt on a second wait" do
      expect(within { task.wait }).to be_a(LLM::Interrupt)
    end

    it "raises the same exception it raised the first time" do
      second = begin
        within { task.wait }
        nil
      rescue LLM::Interrupt => ex
        ex
      end
      expect(second).to equal(interrupted)
    end
  end
end
