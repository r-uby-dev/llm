# frozen_string_literal: true

require "setup"
require "timeout"

##
# What a cancel does to a running `:async` tool.
#
# The task is told, and the reactor is stopped by whoever waits - which is
# the only point at which it is known to be idle, and the point a group
# already stopped it from.
#
# Neither example waits on a clock to find out what happened: the tool says
# when it has started, so an example knows the cancel landed on a running
# tool rather than racing its start, and says when it has finished, so an
# example knows the interrupt ended it rather than leaving it to run on.
#
# Every wait has a deadline. A cancel that silently fails to deliver would
# otherwise be a cell that hangs rather than a failure that names itself,
# and this repository has already spent cells on hangs.
RSpec.describe LLM::Function::Async::Task do
  let(:started) { Queue.new }
  let(:finished) { Queue.new }
  let(:cleaned) { Queue.new }
  let(:told) { Queue.new }
  let(:reactor) { LLM::Function::Async::Reactor.new }
  after { reactor.stop }

  ##
  # A tool that runs until something stops it, saying so at both ends.
  #
  # `sleep` is the scheduler's, so it is a point at which the interrupt can
  # arrive.
  def counting_tool
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

  ##
  # And one that handles the interrupt rather than letting it raise.
  #
  # It yields twice: once before the interrupt can arrive, and again after
  # it has been told, before it returns. The second yield is the point - a
  # tool that answers slowly is the one a teardown can take away from, and
  # the answer has to be pushed before that can happen.
  def rescuing_tool
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

  ##
  # And one that cleans up in its own rescue and raises on, which is what a
  # held cancel has to reach: the tool's rescue, and the caller's exception.
  def cleaning_tool
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

  ##
  # And one whose only notification is the hook under its other name.
  def cancelling_tool
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

  def task_for(tool)
    function = tool.function.dup.tap do |fn|
      fn.id = "call_1"
      fn.arguments = {}
    end
    function.task(:async).tap { |task| task.reactor = reactor }
  end

  def settle(queue, timeout = 5)
    Timeout.timeout(timeout) { queue.pop }
  end

  def within(timeout = 5, &block)
    Timeout.timeout(timeout, &block)
  end

  describe "a tool that lets the interrupt raise" do
    it "is told, and stops running" do
      task = task_for(counting_tool)
      task.spawn
      settle(started)

      task.interrupt!

      expect(settle(finished)).to eq(:done)
    end

    it "raises LLM::Interrupt to the caller" do
      task = task_for(counting_tool)
      task.spawn
      settle(started)

      task.interrupt!

      expect { within { task.wait } }.to raise_error(LLM::Interrupt)
    end

    it "stops the reactor it ran on" do
      task = task_for(counting_tool)
      task.spawn
      settle(started)

      task.interrupt!
      expect { within { task.wait } }.to raise_error(LLM::Interrupt)

      expect(reactor.thread).not_to be_alive
    end
  end

  describe "a tool that handles the interrupt" do
    it "is let to, and answers with its own value" do
      task = task_for(rescuing_tool)
      task.spawn
      settle(started)

      task.interrupt!

      expect(within { task.wait }.to_h[:value]).to eq("ok" => true, "interrupted" => true)
    end
  end

  ##
  # The cancel precedes `spawn`, so it provably precedes the block: there is
  # nothing to ask the scheduler for yet, and the block is where it is taken
  # up. It is spent inside the call now, which is the whole of what this
  # strategy was missing - the block used to raise before `defer_cancel`,
  # which is where the tool is called, so the tool was never entered.
  describe "a cancel that arrives before the tool starts" do
    it "enters the tool before it is interrupted" do
      task = task_for(counting_tool)
      task.interrupt!

      expect(settle(started)).to eq(:in_call)
    end

    it "raises LLM::Interrupt to the caller" do
      task = task_for(counting_tool)
      task.interrupt!

      expect { within { task.wait } }.to raise_error(LLM::Interrupt)
    end

    it "is a no-op for a task that never spawned" do
      task = task_for(counting_tool)
      expect { task.interrupt! }.not_to raise_error
    end

    context "when the tool cleans up in its own rescue" do
      it "is cleaned up" do
        task = task_for(cleaning_tool)
        task.interrupt!
        begin
          within { task.wait }
        rescue LLM::Interrupt
          nil
        end
        expect(settle(cleaned)).to eq(:cleaned_up)
      end

      it "still raises to the caller" do
        task = task_for(cleaning_tool)
        task.interrupt!
        expect { within { task.wait } }.to raise_error(LLM::Interrupt)
      end
    end

    context "when the tool is told through on_cancel" do
      it "is told" do
        task = task_for(cancelling_tool)
        task.interrupt!
        begin
          within { task.wait }
        rescue LLM::Interrupt
          nil
        end
        expect(settle(told)).to eq(:cancelled)
      end
    end
  end

  ##
  # A cancel after the call has returned has nothing to interrupt, and the
  # fiber a task ran in has gone with it.
  describe "a cancel that arrives after the tool has returned" do
    it "is a no-op" do
      task = task_for(rescuing_tool)
      within { task.wait }

      expect(task.interrupt!).to be_nil
    end
  end

  ##
  # A task that has answered has answered for good, which is what `Thread#value`
  # does for the other in-process strategy and what the ractor's task is
  # asserted to do. The queue is popped once, and what it held is kept.
  describe "a task that has been waited on" do
    let(:task) { task_for(rescuing_tool) }
    let(:first) { within { task.wait } }

    before { first }

    it "answers a second wait from the result it has" do
      expect(within { task.wait }).to equal(first)
    end

    it "answers a second wait with what the first one had" do
      expect(within { task.wait }.to_h).to eq(first.to_h)
    end
  end

  ##
  # The exception case is the one that used to block: the first wait raised,
  # and the second waited on a queue that would never fill again.
  describe "a task whose call was interrupted" do
    let(:task) { task_for(counting_tool) }

    ##
    # The exception the first wait raised, which a second one has to raise
    # again rather than waiting on an empty queue.
    let(:first) do
      task.spawn
      settle(started)
      task.interrupt!
      within { task.wait }
      nil
    rescue LLM::Interrupt => ex
      ex
    end

    before { first }

    it "raises LLM::Interrupt on a second wait" do
      expect { within { task.wait } }.to raise_error(LLM::Interrupt)
    end

    it "raises the same exception it raised the first time" do
      second = begin
        within { task.wait }
        nil
      rescue LLM::Interrupt => ex
        ex
      end
      expect(second).to equal(first)
    end
  end
end
