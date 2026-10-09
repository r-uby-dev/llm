# frozen_string_literal: true

require "setup"

##
# The ractor's half of the window's contract.
#
# `spec/function/window_spec.rb` covers the window's three cases unit by
# unit, with a thread standing in for the tool. This covers the window's
# second caller, where the tool runs inside a ractor, and the cases are
# the same three:
#
# - an interrupt that arrives while the tool runs reaches the tool's own
#   `rescue`, and its value comes back;
# - an interrupt that arrives before the tool runs is held until it does,
#   and reaches the tool's `rescue` the same way, rather than being
#   answered early with `{cancelled: true}` for a call that never ran;
# - a tool that does not rescue is answered with a note that names the
#   cancel, because the ractor's own `rescue` answers it - an exception
#   cannot cross a ractor boundary, so the task raises `LLM::Interrupt`
#   where the caller is waiting.
#
# **The held case detects the race rather than ordering it.** Nothing in
# that example orders the interrupt against the ractor reaching
# `running!`, and the tool cannot say that it got there, because a tool
# that signals from inside its own call is the first case, not that one.
# A red run there can mean a scheduler as easily as a broken window; the
# other two can only mean the window.
#
# **"Now" has to cross a ractor boundary.** The window's own spec hands
# its tool a Queue, because both ends of that handover are threads the
# example made. Here the tool runs in another ractor, so the handover is
# a ractor as well: the examples that need one make a gate, hand it to
# the tool on the tool's own class, and wait for the message the way the
# mailbox waits for a reply. A constant rather than an argument, so the
# gate is something the tool reads where it runs rather than something
# the call carries with it. No example sleeps to find out where the call
# has got to.
#
# **Every wait has a deadline.** A raise cannot be relied on to interrupt
# a wait on a ractor, so each of them runs on a thread of its own and is
# joined with a timeout: a ractor that never gets there fails with a
# message rather than hanging the suite.
#
# **The tool holds.** A tool signals and then sleeps, so an interrupt is
# delivered while the tool is inside its own call, rather than after it
# has returned, where the window makes the interrupt a no-op.
RSpec.describe LLM::Function::Ractor::Job do
  ##
  # The parser is compared as it is written rather than as CI spells it,
  # which is `JSON`, so this is not a guard that always skips.
  before do
    skip "not supported by yajl or oj" unless ENV.fetch("JSON_PARSER", "json").downcase == "json"
  end

  ##
  # Runs the block on a thread of its own and joins it, so a wait that
  # never ends is a failure that names the wait rather than a hang.
  def within(seconds = 5, &block)
    thread = Thread.new do
      ##
      # The block is expected to raise: a cancelled call is raised on the
      # caller now, rather than answered with it, so a thread's own report
      # of the exception would be noise.
      Thread.current.report_on_exception = false
      block.call
    end
    thread.join(seconds) ? thread.value : raise("timed out after #{seconds} seconds")
  end

  ##
  # A ractor a tool can signal, and the "now" of the cases that need one.
  # It is not the ractor the example runs on, so a tool's message cannot
  # arrive anywhere else, and one example cannot consume another's.
  def gate
    @gate ||= Ractor.new { Ractor.receive }
  end

  ##
  # The gate's message, waited for the way the mailbox waits for a reply:
  # `take` where the runtime has it, `Ractor.select` where it does not.
  def signal
    gate.respond_to?(:take) ? gate.take : Ractor.select(gate).last
  end

  describe "an interrupt while the tool runs" do
    let(:tool_class) do
      tool_gate = gate
      Class.new(LLM::Tool) do
        name "interruptible"
        const_set(:GATE, tool_gate)

        def call
          self.class::GATE.send([:running])
          sleep 10
          {"ok" => true}
        rescue LLM::Interrupt
          {"ok" => true, "interrupted" => true}
        end
      end
    end

    let(:function) do
      tool_class.function.dup.tap do |fn|
        fn.id = "call_1"
        fn.arguments = {}
      end
    end

    let(:task) { function.task(:ractor) }

    it "reaches the tool's own rescue" do
      task.spawn
      ##
      # Sent from inside the tool's call, so the interrupt is delivered to
      # a tool that is running. This is the case the ractor already
      # delivered, and the case the window must not break.
      within { signal }
      task.interrupt!
      expect(within { task.wait.to_h }).to eq(
        id: "call_1",
        name: "interruptible",
        value: {"ok" => true, "interrupted" => true}
      )
    end
  end

  describe "an interrupt before the tool runs" do
    let(:tool_class) do
      Class.new(LLM::Tool) do
        name "held"

        def call
          sleep 10
          {"ok" => true}
        rescue LLM::Interrupt
          {"ok" => true, "interrupted" => true}
        end
      end
    end

    let(:function) do
      tool_class.function.dup.tap do |fn|
        fn.id = "call_2"
        fn.arguments = {}
      end
    end

    let(:task) { function.task(:ractor) }

    it "is held until the tool runs, and reaches the tool's own rescue" do
      task.spawn
      ##
      # Delivered before the tool has had a chance to open its window, so
      # the window is idle when it arrives. Nothing may answer it in the
      # meantime: a tool that saves its work, or closes what it opened,
      # when it is cancelled is told by its own `rescue`, and loses it if
      # the call is answered early instead.
      task.interrupt!
      expect(within { task.wait.to_h }).to eq(
        id: "call_2",
        name: "held",
        value: {"ok" => true, "interrupted" => true}
      )
    end
  end

  describe "an interrupt and a tool that does not rescue" do
    let(:tool_class) do
      tool_gate = gate
      Class.new(LLM::Tool) do
        name "brittle"
        const_set(:GATE, tool_gate)

        def call
          self.class::GATE.send([:running])
          sleep 10
          {"ok" => true}
        end
      end
    end

    let(:function) do
      tool_class.function.dup.tap do |fn|
        fn.id = "call_3"
        fn.arguments = {}
      end
    end

    let(:group) { LLM::Function::Ractor::Group.new [function.task(:ractor)] }

    it "raises when the call was cancelled" do
      group.spawn
      within { signal }
      group.interrupt!
      expect { within { group.wait } }.to raise_error(LLM::Interrupt)
    end
  end
end
