# frozen_string_literal: true

require "setup"

RSpec.describe LLM::Function::Window do
  describe "an interrupt while the tool is running" do
    it "raises on the thread the tool is running on" do
      handover, gate = Queue.new, Queue.new
      thread = Thread.new do
        window = described_class.new(thread: Thread.current)
        window.running!
        handover << window
        gate.pop
        :returned
      rescue LLM::Interrupt
        :interrupted
      end

      handover.pop.interrupt!
      expect(thread.value).to eq(:interrupted)
    end
  end

  describe "an interrupt before the tool runs" do
    it "is held until the tool opens the window" do
      log, handover, gate = Queue.new, Queue.new, Queue.new
      thread = Thread.new do
        window = described_class.new(thread: Thread.current)
        handover << window
        gate.pop
        window.running!
        log << :opened
        gate.pop
        :returned
      rescue LLM::Interrupt
        log << :interrupted
        :interrupted
      end

      window = handover.pop
      interrupter = Thread.new { window.interrupt! }
      gate << true
      expect(log.pop).to eq(:opened)
      expect(log.pop).to eq(:interrupted)
      expect(thread.value).to eq(:interrupted)
      interrupter.join
    end
  end

  describe "an interrupt after the tool has returned" do
    it "is not raised" do
      handover, gate = Queue.new, Queue.new
      thread = Thread.new do
        window = described_class.new(thread: Thread.current)
        window.running!
        window.finished!
        handover << window
        gate.pop
        :returned
      rescue LLM::Interrupt
        :interrupted
      end

      handover.pop.interrupt!
      gate << true
      expect(thread.value).to eq(:returned)
    end
  end

  describe "a deferred ask when the asker cannot hold one" do
    it "is refused" do
      window = described_class.new(scheduler: Object.new, fiber: Fiber.current)
      expect { window.interrupt!(wait: false) }
        .to raise_error(LLM::FiberError, /fiber_interrupt/)
    end
  end
end
