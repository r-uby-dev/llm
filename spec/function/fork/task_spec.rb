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

  def task_for(tool, id)
    tool.function.dup.tap do |fn|
      fn.id = id
      fn.arguments = {}
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

  describe "a call that has returned" do
    let(:task) { task_for(quick_tool, "call_1") }
    let(:first) { within(task: task) { task.wait } }
    let(:second) { within(task: task) { task.wait } }

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
    let(:task) { task_for(holding_tool, "call_2") }
    let(:first) { raised { within(task: task) { task.wait } } }
    let(:second) { raised { within(task: task) { task.wait } } }

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
  end

  ##
  # The ending a result channel cannot report: the read is an `EOFError` rather
  # than a wait nothing can wake, and it is answered in band rather than raised
  # into the turn.
  describe "a call whose child ended without a result" do
    let(:task) { task_for(dying_tool, "call_3") }
    let(:returned) { within(task: task) { task.wait } }
    let(:second) { within(task: task) { task.wait } }

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
