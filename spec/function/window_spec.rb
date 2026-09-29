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
# The raise is asynchronous and lands on `Thread.main` - which is this
# example's own thread - so each example waits at a blocking call and
# rescues around it. Waiting is the point: a raise arrives at a check
# point, and a sleeping thread is at one.
#
# The interrupt is delivered from a thread of its own, because a held
# interrupt blocks the thread that delivers it. That is what holding
# means.
RSpec.describe LLM::Function::Window do
  subject(:window) { described_class.new }

  def interrupt(window)
    Thread.new { window.interrupt! }
  end

  describe "an interrupt while the tool is running" do
    it "raises on the thread that owns the window" do
      window.running!
      raised = begin
        interrupt(window)
        sleep 0.1
        false
      rescue LLM::Interrupt
        true
      end
      expect(raised).to be(true)
    end
  end

  describe "an interrupt before the tool runs" do
    it "is held rather than answered" do
      thread = interrupt(window)
      sleep 0.05
      expect(thread).to be_alive
    ensure
      thread&.kill
    end

    it "is raised on the tool once it runs" do
      raised = begin
        interrupt(window)
        sleep 0.05
        window.running!
        sleep 0.1
        false
      rescue LLM::Interrupt
        true
      end
      expect(raised).to be(true)
    end
  end

  describe "an interrupt after the tool has returned" do
    it "is not raised" do
      window.running!
      window.finished!
      raised = begin
        interrupt(window)
        sleep 0.1
        false
      rescue LLM::Interrupt
        true
      end
      expect(raised).to be(false)
    end
  end
end
