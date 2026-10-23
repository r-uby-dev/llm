# frozen_string_literal: true

require "setup"
require "async"
require "timeout"

RSpec.describe LLM::Function::Fiber::Task do
  let(:log) { Queue.new }
  let(:started) { Queue.new }
  let(:cleaned) { Queue.new }
  let(:notification) { Async::Notification.new }

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

  let(:cleaning) do
    notification, started, cleaned = self.notification, self.started, self.cleaned
    Class.new(LLM::Tool) do
      name "cleaning"
      define_method(:call) do
        started << :in_call
        notification.wait
        {ok: true}
      rescue LLM::Interrupt
        cleaned << :cleaned_up
        raise
      end
    end
  end

  let(:quick) do
    Class.new(LLM::Tool) do
      name "quick"
      def call
        {ok: true}
      end
    end
  end

  let(:telling) do
    log = self.log
    Class.new(LLM::Tool) do
      name "telling"
      def call
        {ok: true}
      end
      define_method(:on_interrupt) do
        log << :interrupted
      end
    end
  end

  def task_for(tool)
    tool.function.dup.tap do |fn|
      fn.id = "call_1"
      fn.arguments = {}
    end.task(:fiber)
  end

  def settle(queue, timeout = 5)
    Timeout.timeout(timeout) { queue.pop }
  end

  def react(timeout = 5, &block)
    Async do |root|
      root.with_timeout(timeout) do
        block.call
      rescue LLM::Interrupt, StandardError => ex
        ex
      end
    end.wait
  end

  describe "a scheduler that cannot hold a cancel" do
    let(:task) { task_for(holding) }

    before { allow(Fiber).to receive(:scheduler).and_return(Object.new) }

    it "is refused before the fiber is scheduled" do
      expect { task.wait }.to raise_error(LLM::FiberError)
    end
  end

  describe "a cancel that arrives before the call runs" do
    let(:tool) { holding }
    let(:task) { task_for(tool) }
    let(:error) { react { task.wait } }

    before { task.interrupt! }

    it "is held rather than dropped" do
      expect(error).to be_a(LLM::Interrupt)
    end

    it "runs the hook once the call has ended" do
      expect([error.class, log.size]).to eq([LLM::Interrupt, 1])
    end

    context "when the tool cleans up in its own rescue" do
      let(:tool) { cleaning }

      it "enters the tool" do
        error
        expect(settle(started)).to eq(:in_call)
      end

      it "is cleaned up" do
        error
        expect(settle(cleaned)).to eq(:cleaned_up)
      end

      it "still raises to the caller" do
        expect(error).to be_a(LLM::Interrupt)
      end
    end

    context "when the tool answers before anything can reach it" do
      let(:tool) { quick }

      it "leaves the reactor usable" do
        sibling = task_for(quick)
        result = react do
          task.wait
          sibling.spawn
          sibling.wait
        end
        expect(result).to be_a(LLM::Function::Return)
      end

      context "when the tool counts the hook it was told through" do
        let(:tool) { telling }

        it "tells the tool" do
          error
          expect(settle(log)).to eq(:interrupted)
        end
      end
    end
  end

  describe "a cancel that arrives while the call runs" do
    let(:task) { task_for(holding) }

    it "raises at the tool" do
      expect(react do
        task.spawn
        task.interrupt!
        sleep 0.1
        task.wait
      end).to be_a(LLM::Interrupt)
    end
  end

  describe "a cancel that arrives after the call has returned" do
    let(:task) { task_for(quick) }

    it "is a no-op" do
      cancelled = nil
      error = react do
        task.wait
        cancelled = task.interrupt!
      end
      expect([error, cancelled]).to eq([nil, nil])
    end

    it "preserves the result" do
      first = second = nil
      react do
        first = task.wait
        task.interrupt!
        second = task.wait
      end
      expect(second.equal?(first)).to be(true)
    end

    it "does not run the hook" do
      react { task.wait }
      task.interrupt!
      expect(log).to be_empty
    end
  end

  describe "a cancel for a group whose tasks have not been spawned" do
    let(:task) { task_for(holding) }
    let(:group) { LLM::Function::Fiber::Group.new([task]) }

    before { group.interrupt! }

    it "reaches the task" do
      expect(react { group.wait }).to be_a(LLM::Interrupt)
    end
  end
end
