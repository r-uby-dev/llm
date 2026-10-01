# frozen_string_literal: true

require "setup"
require "timeout"

##
# What a forked call answers, and what a second wait is given.
#
# A wait reads the child's result channel once, and the `ensure` around it
# closes both channels - so a second read is an error rather than an answer,
# and what the first wait took is what a second one is given. The interrupt is
# kept the same way: a call that was cancelled re-raises the same exception.
#
# **The half about a call that returned is issue #203.** #202 wrote these
# examples and took them out again: the first wait passes on its own, and the
# same wait hangs once a fork call has been waited on before it in the same
# process - and the run's output could not say which of the two waits it was.
# They are here again, and the wait that runs them says the two things the
# timeout could not: where it stopped, and whether the child it was waiting on
# is still there.
#
# The strategy needs xchan.rb, which is not a dependency of this gem, and the
# examples skip where it is not installed.
RSpec.describe LLM::Function::Fork::Task do
  before do
    LLM.require "xchan", "~> 0.24" unless defined?(::Chan::UNIXSocket)
  rescue LoadError
    skip "xchan.rb is not installed"
  end

  ##
  # Runs the block on a thread of its own and joins it, so a wait that never
  # comes back is a failure that names the wait rather than a hang.
  #
  # A failure says the two things a timeout cannot: whether the child is still
  # running - one that is running has not answered yet, and one that has ended
  # never will - and where the waiter stopped, which separates a read with
  # nothing to read from a lock with no owner.
  def within(seconds = 5, task: nil, &block)
    thread = Thread.new(&block)
    return thread.value if thread.join(seconds)
    raise "timed out after #{seconds} seconds (#{child(task)})\n" \
          "  the waiter was in:\n    #{thread.backtrace&.first(8)&.join("\n    ")}"
  ensure
    thread&.kill if thread&.alive?
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
  # And one that holds, so the interrupt has a running call to land on. The
  # window holds an interrupt that arrives before it, so a cancel does not
  # race the tool's start.
  let(:holding_tool) do
    Class.new(LLM::Tool) do
      name "holding"

      def call
        sleep 5
        {ok: true}
      end
    end
  end

  describe "a call that has returned" do
    let(:task) { task_for(quick_tool, "call_1") }

    it "answers the first wait with the tool's result" do
      expect(within(task: task) { task.wait }.to_h).to eq(
        id: "call_1", name: "quick", value: {ok: true}
      )
    end

    ##
    # The same question with no hook and no `let` between it and the example
    # above: two calls, each waited on once, in one example. If position in
    # the run decides, this is where it shows.
    it "answers two calls in one example" do
      first = task_for(quick_tool, "call_1")
      second = task_for(quick_tool, "call_2")
      expect([
        within(task: first) { first.wait }.to_h,
        within(task: second) { second.wait }.to_h
      ]).to eq([
        {id: "call_1", name: "quick", value: {ok: true}},
        {id: "call_2", name: "quick", value: {ok: true}}
      ])
    end

    ##
    # And the shape the issue names: both spawned before either is waited on,
    # which is what a group does.
    it "answers two calls that were spawned before either was waited on" do
      group = LLM::Function::Fork::Group.new(
        [task_for(quick_tool, "call_1"), task_for(quick_tool, "call_2")]
      )
      group.spawn
      expect(within(task: group) { group.wait.map(&:id) }).to eq(%w[call_1 call_2])
    end

    describe "a second wait" do
      let(:first) { within(task: task) { task.wait } }

      before { first }

      it "is answered from the result the first one took" do
        expect(within(task: task) { task.wait }).to equal(first)
      end

      it "is answered with what the first one had" do
        expect(within(task: task) { task.wait }.to_h).to eq(first.to_h)
      end
    end
  end

  describe "a call that was interrupted" do
    let(:task) { task_for(holding_tool, "call_2") }

    ##
    # The exception the first wait raised, which a second one has to raise
    # again rather than reading a channel that has gone.
    let(:first) do
      task.spawn
      task.interrupt!
      within(task: task) { task.wait }
      nil
    rescue LLM::Interrupt => ex
      ex
    end

    before { first }

    it "raises LLM::Interrupt on the first wait" do
      expect(first).to be_a(LLM::Interrupt)
    end

    it "raises LLM::Interrupt on a second wait" do
      expect { within(task: task) { task.wait } }.to raise_error(LLM::Interrupt)
    end

    it "raises the same exception the first one raised" do
      second = begin
        within(task: task) { task.wait }
        nil
      rescue LLM::Interrupt => ex
        ex
      end
      expect(second).to equal(first)
    end
  end
end
