# frozen_string_literal: true

require "setup"
require "timeout"

RSpec.describe LLM::Function::Fork::Task do
  before do
    LLM.require "xchan", "~> 0.24" unless defined?(::Chan::UNIXSocket)
  rescue LoadError
    skip "xchan.rb is not installed"
  end

  def within(seconds = 5, task: nil, &block)
    thread = Thread.new(&block)
    thread.report_on_exception = false
    return thread.value if thread.join(seconds)
    raise "timed out after #{seconds} seconds (#{child(task)})\n" \
          "  the waiter was in:\n    #{thread.backtrace&.first(8)&.join("\n    ")}"
  ensure
    thread&.kill if thread&.alive?
  end

  def raised
    yield
    nil
  rescue LLM::Interrupt => ex
    ex
  end

  def child(task)
    return "no call was named" if task.nil?
    task.alive? ? "the child is still running" : "the child has ended"
  end

  def task_for(tool, id, tracer: nil)
    tool.function.dup.tap do |fn|
      fn.id = id
      fn.arguments = {}
      fn.tracer = tracer if tracer
    end.task(:fork)
  end

  let(:quick_tool) do
    Class.new(LLM::Tool) do
      name "quick"

      def call
        {ok: true}
      end
    end
  end

  let(:holding_tool) do
    Class.new(LLM::Tool) do
      name "holding"

      def call
        sleep 5
        {ok: true}
      end
    end
  end

  let(:recording_tool) do
    Class.new(LLM::Tool) do
      name "recording"

      def call
        @entered = true
        sleep 5
        {ok: true}
      rescue LLM::Interrupt
        {entered: @entered, told: @told, rescued: true}
      end

      def on_interrupt
        @told = true
      end
    end
  end

  let(:dying_tool) do
    Class.new(LLM::Tool) do
      name "dying"

      def call
        exit!(3)
      end
    end
  end

  let(:provider) { LLM.openai(key: "test") }
  let(:tracer) { recorder.new(provider) }
  let(:recorder) do
    Class.new(LLM::Tracer) do
      attr_reader :interrupts

      def initialize(...)
        super
        @interrupts = []
      end

      def on_tool_start(id:, name:, arguments:, model:)
        "span:#{id}"
      end

      def on_tool_interrupt(ex:, span:, started_at:, finished_at:)
        @interrupts << [ex, span]
        nil
      end

      def on_tool_finish(result:, span:, started_at:, finished_at:)
        nil
      end

      def on_tool_error(ex:, span:, started_at:, finished_at:)
        nil
      end
    end
  end

  describe "a call that has returned" do
    let(:task) { task_for(quick_tool, "call_1") }
    let(:first) { within(task:) { task.wait } }
    let(:second) { within(task:) { task.wait } }

    before { first }

    it "answers the first wait with the tool's result" do
      expect(first.to_h).to eq(id: "call_1", name: "quick", value: {ok: true})
    end

    it "answers a second wait from the result the first one took" do
      expect(second).to equal(first)
    end

    it "answers a second wait with what the first one had" do
      expect(second.to_h).to eq(first.to_h)
    end
  end

  describe "two calls waited on in one example" do
    let(:first) { task_for(quick_tool, "call_1") }
    let(:second) { task_for(quick_tool, "call_2") }
    let(:waited) do
      [
        within(task: first) { first.wait }.to_h,
        within(task: second) { second.wait }.to_h
      ]
    end

    it "answers each call with its own result" do
      expect(waited).to eq([
        {id: "call_1", name: "quick", value: {ok: true}},
        {id: "call_2", name: "quick", value: {ok: true}}
      ])
    end
  end

  describe "two calls spawned before either is waited on" do
    let(:group) do
      LLM::Function::Fork::Group.new(
        [task_for(quick_tool, "call_1"), task_for(quick_tool, "call_2")]
      )
    end
    let(:ids) { within(task: group) { group.wait.map(&:id) } }

    before { group.spawn }

    it "answers them in the order they were asked for" do
      expect(ids).to eq(%w[call_1 call_2])
    end
  end

  describe "a call that was interrupted" do
    let(:task) { task_for(holding_tool, "call_2", tracer:) }
    let(:group) { task.group_class.new([task]) }
    let(:first) { within(task:) { task.wait } }
    let(:second) { within(task:) { task.wait } }

    before do
      task.spawn
      task.interrupt!
      first
    end

    it "answers with LLM::Interrupt on the first wait" do
      expect(first).to be_a(LLM::Interrupt)
    end

    it "answers with LLM::Interrupt on a second wait" do
      expect(second).to be_a(LLM::Interrupt)
    end

    it "answers the same exception the first one answered" do
      expect(second).to equal(first)
    end

    it "announces the interrupt where the group waits" do
      raised { group.wait }
      expect(tracer.interrupts.size).to eq(1)
    end
  end

  describe "a call that was cancelled while the child was starting" do
    let(:task) { task_for(recording_tool, "call_4") }
    let(:returned) { within(task:) { task.wait } }

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

  describe "a call cancelled while the child was starting that does not rescue" do
    let(:task) { task_for(holding_tool, "call_5") }
    let(:error) { raised { within(task:) { task.wait } } }

    before do
      task.spawn
      task.interrupt!
    end

    it "gives the caller LLM::Interrupt" do
      expect(within(task:) { task.wait }).to be_a(LLM::Interrupt)
    end
  end

  describe "a call cancelled before it was spawned" do
    let(:task) { task_for(recording_tool, "call_6") }
    let(:returned) { within(task:) { task.wait } }

    before do
      task.interrupt!
      task.spawn
      returned
    end

    it "enters the tool" do
      expect(returned.value[:entered]).to be(true)
    end

    it "runs the tool's own rescue" do
      expect(returned.value[:rescued]).to be(true)
    end
  end

  describe "a group cancelled before its tasks were spawned" do
    let(:group) do
      LLM::Function::Fork::Group.new([task_for(recording_tool, "call_7")])
    end
    let(:returned) { within(task: group) { group.wait.first } }

    before do
      group.interrupt!
      group.spawn
      returned
    end

    it "enters the tool" do
      expect(returned.value[:entered]).to be(true)
    end

    it "runs the tool's own rescue" do
      expect(returned.value[:rescued]).to be(true)
    end
  end

  describe "a call whose child ended without a result" do
    let(:task) { task_for(dying_tool, "call_3") }
    let(:returned) { within(task:) { task.wait } }
    let(:second) { within(task:) { task.wait } }

    before { returned }

    it "answers with an error return rather than raising" do
      expect(returned.error?).to be(true)
    end

    it "names the read that ended" do
      expect(returned.value[:type]).to eq("EOFError")
    end

    it "says the tool exited unexpectedly" do
      expect(returned.value[:message]).to eq("the tool exited unexpectedly")
    end

    it "answers a second wait with the same return" do
      expect(second).to equal(returned)
    end
  end
end
