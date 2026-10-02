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

  ##
  # And one that handles the interrupt rather than letting it raise.
  #
  # It yields twice: once before the interrupt can arrive, and again after
  # it has been told, before it returns. The second yield is the point - a
  # tool that answers slowly is the one a teardown can take away from, and
  # the answer has to be pushed before that can happen.
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

  ##
  # And one that cleans up in its own rescue and raises on, which is what a
  # held cancel has to reach: the tool's rescue, and the caller's exception.
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

  ##
  # And one whose only notification is the hook under its other name.
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

  ##
  # The cancel precedes `spawn`, so it provably precedes the block: there is
  # nothing to ask the scheduler for yet, and the block is where it is taken
  # up. It is spent inside the call now, which is the whole of what this
  # strategy was missing - the block used to raise before `defer_cancel`,
  # which is where the tool is called, so the tool was never entered.
  describe "a cancel that arrives before the call runs" do
    before { task.interrupt! }

    it "enters the tool" do
      expect(settle(started)).to eq(:in_call)
    end

    it "raises LLM::Interrupt to the caller" do
      expect { within { task.wait } }.to raise_error(LLM::Interrupt)
    end

    it "is a no-op for a task that never spawned" do
      expect { task.interrupt! }.not_to raise_error
    end

    context "when the tool cleans up in its own rescue" do
      let(:tool) { cleaning }

      it "is cleaned up" do
        expect(settle(cleaned)).to eq(:cleaned_up)
      end

      it "still raises to the caller" do
        expect { within { task.wait } }.to raise_error(LLM::Interrupt)
      end
    end

    context "when the tool is told through on_cancel" do
      let(:tool) { cancelling }

      it "is told" do
        expect(settle(told)).to eq(:cancelled)
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

    it "is told, and stops running" do
      expect(settle(finished)).to eq(:done)
    end

    it "raises LLM::Interrupt to the caller" do
      expect { within { task.wait } }.to raise_error(LLM::Interrupt)
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

  ##
  # A cancel after the call has returned has nothing to interrupt, and the
  # fiber a task ran in has gone with it.
  describe "a cancel that arrives after the call has returned" do
    let(:tool) { rescuing }

    before { within { task.wait } }

    it "is a no-op" do
      expect(task.interrupt!).to be_nil
    end
  end

  ##
  # A task that has answered has answered for good, which is what `Thread#value`
  # does for the other in-process strategy and what the ractor's task is
  # asserted to do. The queue is popped once, and what it held is kept.
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

  ##
  # The exception case is the one that used to block: the first wait raised,
  # and the second waited on a queue that would never fill again.
  describe "a task whose call was interrupted" do
    ##
    # The exception the first wait raised, which a second one has to raise
    # again rather than waiting on an empty queue.
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
      expect { within { task.wait } }.to raise_error(LLM::Interrupt)
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
