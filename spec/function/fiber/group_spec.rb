# frozen_string_literal: true

require "setup"
require "async"

RSpec.describe LLM::Function::Fiber::Group do
  let(:log) { Queue.new }
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

  let(:quick) do
    Class.new(LLM::Tool) do
      name "quick"
      def call
        {ok: true}
      end
    end
  end

  def task_for(tool, id)
    tool.function.dup.tap do |fn|
      fn.id = id
      fn.arguments = {}
    end.task(:fiber)
  end

  def react(timeout = 5, &block)
    error = nil
    Async do |root|
      root.with_timeout(timeout) do
        block.call
      rescue LLM::Interrupt, StandardError => ex
        error = ex
      end
    end
    error
  end

  describe "a group of calls that answer" do
    it "answers with a return for each of them" do
      group = described_class.new([task_for(quick, "call_1"), task_for(quick, "call_2")])
      returns = nil
      error = react { returns = group.wait }
      expect([error, returns.map(&:id)]).to eq([nil, %w[call_1 call_2]])
    end
  end

  describe "a cancel before the group is spawned" do
    it "reaches a task that has not started" do
      group = described_class.new([task_for(holding, "call_1")])
      group.interrupt!
      error = react { group.wait }
      expect(error).to be_a(LLM::Interrupt)
    end
  end

  describe "a cancel for a group with a returned call in it" do
    it "reaches the calls after the one that has returned" do
      finished = task_for(quick, "call_1")
      parked = task_for(holding, "call_2")
      group = described_class.new([finished, parked])
      error = react do
        group.spawn
        finished.wait
        group.interrupt!
        sleep 0.1
      end
      expect([error, log.size]).to eq([nil, 1])
    end
  end
end
