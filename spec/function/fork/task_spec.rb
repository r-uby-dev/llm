# frozen_string_literal: true

require "setup"
require "timeout"

##
# A task that has answered answers again, for a forked call.
#
# The wait reads the child's result channel once, and the `ensure` around it
# closes both channels - so a second read is an error rather than an answer,
# and what the first wait took is kept instead. The interrupt is kept the same
# way: a call that was cancelled re-raises the same exception on every wait.
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

  ##
  # A call that returns at once, so that the task has an answer to keep.
  let(:quick) do
    Class.new(LLM::Tool) do
      name "quick"

      def call
        {ok: true}
      end
    end.function.dup.tap do |fn|
      fn.id = "call_1"
      fn.arguments = {}
    end.task(:fork)
  end

  ##
  # And one that holds, so that the interrupt has a running call to land on.
  # The window holds an interrupt that arrives before it, so the cancel does
  # not race the tool's start.
  let(:holding) do
    Class.new(LLM::Tool) do
      name "holding"

      def call
        sleep 5
        {ok: true}
      end
    end.function.dup.tap do |fn|
      fn.id = "call_2"
      fn.arguments = {}
    end.task(:fork)
  end

  describe "a call that has returned" do
    it "answers a second wait from the result it has" do
      first = within { quick.wait }
      expect(within { quick.wait }).to equal(first)
    end

    it "answers a second wait with what the first one had" do
      first = within { quick.wait }
      expect(within { quick.wait }.to_h).to eq(first.to_h)
    end
  end

  describe "a call that was interrupted" do
    it "raises the same exception on a second wait" do
      holding.spawn
      holding.interrupt!

      first = begin
        within { holding.wait }
        nil
      rescue LLM::Interrupt => ex
        ex
      end
      second = begin
        within { holding.wait }
        nil
      rescue LLM::Interrupt => ex
        ex
      end
      expect([first.class, second.equal?(first)]).to eq([LLM::Interrupt, true])
    end
  end
end
