# frozen_string_literal: true

require "setup"
require "timeout"

##
# What a cancel does to a running `:async` tool.
#
# The task is told, and the reactor is stopped with it. Neither example
# waits on a clock to find out: the tool says when it has started, so an
# example knows the cancel landed on a running tool rather than racing its
# start, and says when it has finished, so an example knows the interrupt
# ended it rather than leaving it to run on.
RSpec.describe LLM::Function::Async::Task do
  let(:started) { Queue.new }
  let(:finished) { Queue.new }
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
  def rescuing_tool
    started = self.started
    Class.new(LLM::Tool) do
      name "rescuing"
      define_method(:call) do
        started << :in_call
        sleep 10
        {"ok" => true}
      rescue LLM::Interrupt
        {"ok" => true, "interrupted" => true}
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

      expect { task.wait }.to raise_error(LLM::Interrupt)
    end

    it "stops the reactor it ran on" do
      task = task_for(counting_tool)
      task.spawn
      settle(started)

      task.interrupt!
      expect { task.wait }.to raise_error(LLM::Interrupt)

      expect(reactor.thread).not_to be_alive
    end
  end

  describe "a tool that handles the interrupt" do
    it "is let to, and answers with its own value" do
      task = task_for(rescuing_tool)
      task.spawn
      settle(started)

      task.interrupt!

      expect(task.wait.to_h[:value]).to eq("ok" => true, "interrupted" => true)
    end
  end
end
