# frozen_string_literal: true

require "setup"

RSpec.describe LLM::Function::Ractor::Task do
  before do
    skip "not supported by oj" unless ENV.fetch("JSON_PARSER", "json").downcase == "json"
  end

  let(:task) do
    Class.new(LLM::Tool) do
      name "quick"

      def call
        {ok: true}
      end
    end.function.dup.tap do |fn|
      fn.id = "call_1"
      fn.arguments = {}
    end.task(:ractor)
  end

  describe "a task that has been waited on" do
    it "answers a second wait from the result it has" do
      first = within { task.wait }
      expect(within { task.wait }).to equal(first)
    end

    it "answers a second wait with what the first one had" do
      first = within { task.wait }
      expect(within { task.wait }.to_h).to eq(first.to_h)
    end

    it "answers alive? from the result it has" do
      within { task.wait }
      expect(within { task.alive? }).to be(false)
    end
  end

  describe "a wait that arrives after the ractor exits" do
    it "still receives the result after exit monitoring has completed" do
      task.spawn
      within { sleep 0.001 while task.alive? }
      expect(within { task.wait }.to_h).to eq(
        id: "call_1", name: "quick", value: {ok: true}
      )
    end
  end

  describe "concurrent exit monitoring and result retrieval" do
    it "returns results while the exit watcher is active" do
      20.times do
        fn = Class.new(LLM::Tool) do
          name "quick"
          def call = {ok: true}
        end.function.dup
        fn.id = "call_1"
        fn.arguments = {}
        current = fn.task(:ractor)
        current.spawn
        expect(within { current.wait }.value).to eq(ok: true)
      end
    end
  end

  describe "a result sent before the ractor exits" do
    it "returns the result without waiting for ractor termination" do
      allow(task).to receive(:build_task) do |port|
        Ractor.new(port) do |resultp|
          resultp.send([:done, "call_1", "quick", {ok: true}, 1.0])
          Ractor.receive
        end
      end
      expect(within(0.5) { task.wait }.value).to eq(ok: true)
    ensure
      task.instance_variable_get(:@ractor)&.send(:stop)
    end
  end

  describe "a ractor that exits before returning a result" do
    it "returns an error instead of waiting forever" do
      allow(task).to receive(:build_task).and_return(Ractor.new { raise "failed before result" })
      expect(within { task.wait }.to_h).to eq(
        id: "call_1", name: "quick",
        value: {error: true, type: "ractor ended without result"}
      )
      expect(within { sleep 0.001 while task.alive? }).to be_nil
    end
  end

  describe "a task that has returned" do
    it "answers a cancel with nil rather than a raise" do
      within { task.wait }
      expect(within { task.interrupt! }).to be_nil
    end
  end

  let(:recording_tool) do
    Class.new(LLM::Tool) do
      name "recording"

      def call
        @entered = true
        sleep 2
        {ok: true}
      rescue LLM::Interrupt
        {entered: @entered, told: @told, rescued: true}
      end

      def on_interrupt
        @told = true
      end
    end
  end

  let(:holding_tool) do
    Class.new(LLM::Tool) do
      name "holding"

      def call
        sleep 2
        {ok: true}
      end
    end
  end

  describe "a call that was cancelled while the tool was starting" do
    let(:task) do
      recording_tool.function.dup.tap do |fn|
        fn.id = "call_2"
        fn.arguments = {}
      end.task(:ractor)
    end
    let(:returned) { within { task.wait } }

    before do
      task.spawn
      task.interrupt!
      returned
    end

    it "enters the tool" do
      expect(returned.value[:entered]).to be(true)
    end

    it "runs the tool's own rescue" do
      expect(returned.value[:rescued]).to be(true)
    end

    it "tells the tool before the raise lands" do
      expect(returned.value[:told]).to be(true)
    end
  end

  describe "a call cancelled while the tool was starting that does not rescue" do
    let(:task) do
      holding_tool.function.dup.tap do |fn|
        fn.id = "call_3"
        fn.arguments = {}
      end.task(:ractor)
    end
    let(:group) { LLM::Function::Ractor::Group.new([task]) }

    before do
      group.spawn
      group.interrupt!
    end

    it "raises LLM::Interrupt" do
      expect { within { group.wait } }.to raise_error(LLM::Interrupt)
    end
  end

  describe "a call cancelled before it was spawned" do
    let(:task) do
      holding_tool.function.dup.tap do |fn|
        fn.id = "call_4"
        fn.arguments = {}
      end.task(:ractor)
    end
    let(:group) { LLM::Function::Ractor::Group.new([task]) }

    before do
      group.interrupt!
      group.spawn
    end

    it "raises LLM::Interrupt" do
      expect { within { group.wait } }.to raise_error(LLM::Interrupt)
    end
  end

  def within(seconds = 5, &block)
    thread = Thread.new do
      Thread.current.report_on_exception = false
      block.call
    end
    unless thread.join(seconds)
      stacks = Thread.list.filter_map do |t|
        next if t == Thread.current
        "thread #{t.object_id} (#{t.status}):\n#{t.backtrace&.first(10)&.join("\n") || "(unavailable)"}"
      end
      ractor = task.instance_variable_get(:@ractor)
      raise "timed out after #{seconds} seconds; ractor: #{ractor&.inspect}; " \
        "exited: #{task.instance_variable_get(:@exited).inspect}; " \
        "result port: #{task.instance_variable_get(:@resultp)&.inspect}; " \
        "exit port: #{task.instance_variable_get(:@exitp)&.inspect}; " \
        "thread stacks:\n#{stacks.join("\n\n")}"
    end
    thread.value
  end
end
