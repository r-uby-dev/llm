# frozen_string_literal: true

require "setup"
require "timeout"

##
# What a forked call answers, and what a second wait is given.
#
# A wait reads the child's result channel once, and the `ensure` around it
# closes both channels - so a second read is an error rather than an answer,
# and a call that was cancelled re-raises the same exception. A child that
# ended without writing is answered in band, the way a tool that raised is.
#
# **A cancel that arrives while the child is starting is held, not dropped**:
# the control message is a datagram, so it waits in the channel until the
# child's watcher reads it, and the watcher waits on the window the child opens
# immediately before the call. The record of what happened is written on the
# result channel, because a fork's copy of a tool is not the object the parent
# holds.
#
# **Where the raise lands is the tool's shape as well as the window's.** The
# window promises that a raise is not issued *before* the call; the dispatch is
# code, and a raise can land in it. What puts it after the tool's first
# instruction here is that the tool yields - the watcher is woken by
# `running!`, but it cannot take the GVL until the child's main thread gives it
# up, which is the `sleep`. A raise that landed in the dispatch would take the
# job's own `rescue` branch and write `[:interrupt]`, so the group below would
# fail whole rather than one example.
#
# The half about a call that returned is issue #203, and the order below is the
# failing run's order: the first wait is one example, the second waits are the
# next two, and everything else this file asks for runs after them.
RSpec.describe LLM::Function::Fork::Task do
  before do
    LLM.require "xchan", "~> 0.24" unless defined?(::Chan::UNIXSocket)
  rescue LoadError
    skip "xchan.rb is not installed"
  end

  ##
  # Runs the block on a thread of its own and joins it, so a wait that never
  # comes back is a failure that names the wait rather than a hang. It says
  # whether the child is still running, and where the waiter stopped.
  #
  # The interrupt examples raise inside the thread on purpose, so the thread is
  # told not to report its own ending - the example is the report.
  def within(seconds = 5, task: nil, &block)
    thread = Thread.new(&block)
    thread.report_on_exception = false
    return thread.value if thread.join(seconds)
    raise "timed out after #{seconds} seconds (#{child(task)})\n" \
          "  the waiter was in:\n    #{thread.backtrace&.first(8)&.join("\n    ")}"
  ensure
    thread&.kill if thread&.alive?
  end

  ##
  # The exception a block raised, or nil, so an example asserts on an ending
  # rather than performing one.
  def raised
    yield
    nil
  rescue LLM::Interrupt => ex
    ex
  end

  ##
  # @return [String]
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

  ##
  # A call that returns at once, so the task has an answer to keep.
  let(:quick_tool) do
    Class.new(LLM::Tool) do
      name "quick"

      def call
        {ok: true}
      end
    end
  end

  ##
  # A call that holds, so an interrupt has a running call to land on.
  let(:holding_tool) do
    Class.new(LLM::Tool) do
      name "holding"

      def call
        sleep 5
        {ok: true}
      end
    end
  end

  ##
  # A call that records what reached it. The hook writes a flag and the rescue
  # reads it back, so the record says both that the rescue ran and that the
  # hook was written first - which is the order the job's watcher promises, and
  # the reason a tool that releases a resource has released it by the time the
  # raise lands.
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

  ##
  # A call that ends the process it runs in before it writes anything: `exit!`
  # runs no `ensure`, so the child is gone with nothing written.
  let(:dying_tool) do
    Class.new(LLM::Tool) do
      name "dying"

      def call
        exit!(3)
      end
    end
  end

  ##
  # A tracer that counts the endings it is told about, which is the only thing
  # a call being waited on twice should change: the endings belong to the call,
  # and the waits are the caller's.
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

      def on_tool_interrupt(ex:, span:)
        @interrupts << [ex, span]
        nil
      end

      def on_tool_finish(result:, span:)
        nil
      end

      def on_tool_error(ex:, span:)
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

  ##
  # Two calls, each waited on once, in one example - the same question the
  # group above asks, with no hook between the two waits.
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

  ##
  # Both calls spawned before either is waited on, which is what a group does.
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

  ##
  # The interrupt is kept as the exception the first wait raised, and a second
  # wait re-raises that same one rather than reading a channel that has gone.
  describe "a call that was interrupted" do
    let(:task) { task_for(holding_tool, "call_2", tracer:) }
    let(:first) { raised { within(task:) { task.wait } } }
    let(:second) { raised { within(task:) { task.wait } } }

    before do
      task.spawn
      task.interrupt!
      first
    end

    it "raises LLM::Interrupt on the first wait" do
      expect(first).to be_a(LLM::Interrupt)
    end

    it "raises LLM::Interrupt on a second wait" do
      expect(second).to be_a(LLM::Interrupt)
    end

    it "raises the same exception the first one raised" do
      expect(second).to equal(first)
    end

    ##
    # The ending is the call's and the waits are the caller's, so a second wait
    # that re-raises the same exception is not a second ending - which is why
    # the announcement is made where the exception is built.
    it "announces the interrupt once, however many times it is waited on" do
      second
      expect(tracer.interrupts.size).to eq(1)
    end
  end

  ##
  # The cancel follows `spawn` by as little as the file can say, so the child
  # is still starting when the message is written: the watcher reads it before
  # it has the call running, and waits on a window that is still idle. What the
  # tool recorded comes back on the result channel, which is what a rescue that
  # answers rather than raises is for here.
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

  ##
  # And the same cancel on a call that does not rescue: the interrupt escapes
  # the tool, the child writes that on the result channel, and the caller is
  # given it.
  describe "a call cancelled while the child was starting that does not rescue" do
    let(:task) { task_for(holding_tool, "call_5") }
    let(:error) { raised { within(task:) { task.wait } } }

    before do
      task.spawn
      task.interrupt!
    end

    it "gives the caller LLM::Interrupt" do
      expect(error).to be_a(LLM::Interrupt)
    end
  end

  ##
  # The cancel precedes `spawn`, so it is written by `spawn` rather than by the
  # cancel itself: the channels do not exist yet, and building them here would
  # open a socketpair for a task that may never fork. The child is the reader,
  # and the message waits in the channel until its watcher looks.
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

  ##
  # And the same cancel on a group before its tasks are spawned, which is the
  # path the runtime has: a group cancels every task it holds, spawned or not.
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

  ##
  # The ending a result channel cannot report: the read is an `EOFError` rather
  # than a wait nothing can wake, and it is answered in band rather than raised
  # into the turn.
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
