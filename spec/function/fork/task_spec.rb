# frozen_string_literal: true

require "setup"
require "timeout"

##
# A task that has answered answers again, for a forked call.
#
# The wait reads the child's result channel once, and the `ensure` around it
# closes both channels - so a second read is an error rather than an answer,
# and what the first wait took is what a second one is given. The interrupt is
# kept the same way: a call that was cancelled re-raises the same exception.
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
  def within(seconds = 5, &block)
    thread = Thread.new(&block)
    thread.join(seconds) ? thread.value : raise("timed out after #{seconds} seconds")
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
    let(:first) { within { task.wait } }

    before { first }

    it "answers a second wait from the result it has" do
      expect(within { task.wait }).to equal(first)
    end

    it "answers a second wait with what the first one had" do
      expect(within { task.wait }.to_h).to eq(first.to_h)
    end
  end

  describe "a call that was interrupted" do
    let(:task) { task_for(holding_tool, "call_2") }

    ##
    # The exception the first wait raised, which a second one has to raise
    # again rather than reading a channel that has gone.
    let(:first) do
      within { task.wait }
      nil
    rescue LLM::Interrupt => ex
      ex
    end

    before do
      task.spawn
      task.interrupt!
      first
    end

    it "raises LLM::Interrupt on a second wait" do
      expect { within { task.wait } }.to raise_error(LLM::Interrupt)
    end

    it "raises the same exception it raised the first time" do
      second = begin
        within { task.wait }
        nil
      rescue LLM::Interrupt => ex
        ex
      end
      expect(second).to equal(first)
    end
  end
end
