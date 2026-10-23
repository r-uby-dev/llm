# frozen_string_literal: true

require "setup"

RSpec.describe LLM::Function::Ractor::Job do
  before do
    skip "not supported by oj" unless ENV.fetch("JSON_PARSER", "json").downcase == "json"
  end

  def within(seconds = 5, &block)
    thread = Thread.new do
      Thread.current.report_on_exception = false
      block.call
    end
    thread.join(seconds) ? thread.value : raise("timed out after #{seconds} seconds")
  end

  def gate
    @gate ||= Ractor.new { Ractor.receive }
  end

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
