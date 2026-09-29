# frozen_string_literal: true

require "setup"

##
# The window's three cases.
#
# A raise cannot be aimed at a region of code, only permitted for one, so
# these examples are about when it is permitted: while the tool runs it is
# raised, before the tool runs it is held, and once the tool has returned
# it is not raised at all.
#
# **The window names the thread it raises on, and every example here names
# one of its own.** A thread stands in for the tool, builds the window
# (because the window has to name it and it does not exist until the block
# is running), and is joined at the end for the value it returned. Nothing
# waits on a clock, and no example arranges for a raise to land on the
# thread RSpec is running on.
#
# **The held case is checked by an order rather than by a return value.**
# `:interrupted` comes back whether the window held the interrupt until the
# tool ran or answered it the moment it arrived - the difference is whether
# the tool got to open the window first, and only a log says which.
#
# `gate` is how an example says "now": the tool blocks on it, so the window
# is open for as long as the example wants and closes when the example says
# so. Where an example does not push it a second time, the thread is left
# blocked at a check point, which is where an arriving raise lands.
RSpec.describe LLM::Function::Window do
  describe "an interrupt while the tool is running" do
    it "raises on the thread the tool is running on" do
      handover, gate = Queue.new, Queue.new
      thread = Thread.new do
        window = described_class.new(thread: Thread.current)
        window.running!
        ##
        # Handed over after `running!`, so an example that pops it knows
        # the window is open rather than waiting to find out.
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
      ##
      # Delivered while the window is idle, so it waits rather than
      # raising - and it cannot return before the tool opens the window,
      # whatever order the two threads reach their next instruction in.
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
end
