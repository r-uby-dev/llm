# frozen_string_literal: true

require "setup"
require "async"
require "timeout"

##
# The four moments a cancel can arrive in, for a fiber.
#
# `interrupt!` was guarded by `@fiber&.alive?`, so a cancel that arrived
# before `spawn` - when there is no fiber to raise on - was dropped and the
# tool ran as if nothing had happened. The examples run inside a reactor
# because Ruby ships no default `Fiber.scheduler`, and `Async` is what
# installs the only kind there is.
#
# `react` answers with the exception a block ended with rather than raising,
# and `error` is that answer: the block runs inside the reactor, where a raise
# is logged and never reaches RSpec.
RSpec.describe LLM::Function::Fiber::Task do
  let(:log) { Queue.new }
  let(:started) { Queue.new }
  let(:cleaned) { Queue.new }
  let(:notification) { Async::Notification.new }

  ##
  # A tool that holds at a notification the example never sends, and counts
  # the interrupt it was told about. A notification yields to the scheduler,
  # which is what parks the call rather than blocking the thread.
  let(:holding) do
    notification, log = self.notification, self.log
    Class.new(LLM::Tool) do
      name "holding"
      define_method(:call) do
        notification.wait
        {ok: true}
      end
      define_method(:on_interrupt) do
        log << :interrupted
      end
    end
  end

  ##
  # A tool that says it has started, holds at the notification, and cleans up
  # in its own rescue before raising on - which is what a held cancel has to
  # reach: the tool's rescue, and the caller's exception.
  let(:cleaning) do
    notification, started, cleaned = self.notification, self.started, self.cleaned
    Class.new(LLM::Tool) do
      name "cleaning"
      define_method(:call) do
        started << :in_call
        notification.wait
        {ok: true}
      rescue LLM::Interrupt
        cleaned << :cleaned_up
        raise
      end
    end
  end

  ##
  # A tool that answers at once, so the call has returned before the cancel
  # arrives.
  let(:quick) do
    Class.new(LLM::Tool) do
      name "quick"
      def call
        {ok: true}
      end
    end
  end

  def task_for(tool)
    tool.function.dup.tap do |fn|
      fn.id = "call_1"
      fn.arguments = {}
    end.task(:fiber)
  end

  ##
  # A queue read that cannot wait forever, as the other strategies' specs have.
  def settle(queue, timeout = 5)
    Timeout.timeout(timeout) { queue.pop }
  end

  ##
  # Runs the block inside a reactor and answers with the exception it ended
  # with. Expectations are made on what this returns rather than inside the
  # block, because a raise under `Async` is logged and never reaches RSpec - so
  # an example that asserts in there can pass having measured nothing.
  #
  # The interrupt is named rather than left to `rescue => ex`, which reaches
  # only `StandardError` - and an interrupt sits outside it, so a bare rescue
  # here would let the very exception the examples are about walk out of the
  # reactor and fail the example from the outside.
  def react(timeout = 5, &block)
    error = nil
    Async do |root|
      root.with_timeout(timeout) do
        block.call
      rescue LLM::Interrupt, StandardError => ex
        error = ex
      end
    end
    error
  end

  ##
  # A scheduler that cannot be asked for a raise is refused in `spawn`, in the
  # caller's hands - not where the window is built, which is inside the fiber,
  # where the refusal would be an exception the fiber ends with and a caller
  # waiting on a queue nothing fills. The scheduler is answered for rather
  # than installed, since the reactor installs its own.
  describe "a scheduler that cannot hold a cancel" do
    let(:task) { task_for(holding) }

    before { allow(Fiber).to receive(:scheduler).and_return(Object.new) }

    it "is refused before the fiber is scheduled" do
      expect { task.wait }.to raise_error(LLM::FiberError)
    end
  end

  ##
  # The tool is entered now, which is the whole of what this strategy was
  # missing: the fiber raised before the call was reached, so a tool that
  # cleans up in its own rescue never ran its rescue.
  describe "a cancel that arrives before the call runs" do
    let(:tool) { holding }
    let(:task) { task_for(tool) }
    let(:error) { react { task.wait } }

    before { task.interrupt! }

    it "is held rather than dropped" do
      expect(error).to be_a(LLM::Interrupt)
    end

    ##
    # The hook is counted rather than waited on: it runs in the fiber's
    # `ensure`, so it has run by the time the wait has answered.
    it "runs the hook once the call has ended" do
      expect([error.class, log.size]).to eq([LLM::Interrupt, 1])
    end

    context "when the tool cleans up in its own rescue" do
      let(:tool) { cleaning }

      it "enters the tool" do
        error
        expect(settle(started)).to eq(:in_call)
      end

      it "is cleaned up" do
        error
        expect(settle(cleaned)).to eq(:cleaned_up)
      end

      it "still raises to the caller" do
        expect(error).to be_a(LLM::Interrupt)
      end
    end

    ##
    # A tool that never suspends is one the raise cannot land inside: the ask
    # is issued when the call opens, and the scheduler schedules the raise
    # rather than issuing it - so what is left is a raise with no suspension to
    # land on inside the call, and the call has answered by the time the fiber
    # reaches one.
    #
    # What this asserts is the half anything outside the call could notice: the
    # frame that waits on the task ends cleanly, and a sibling task on the same
    # reactor runs. **The raise's own fate is not measured here** - it is aimed
    # at the fiber the tool runs in, and this frame is a different fiber, so
    # `nil` is what a delivered raise and a discarded one both look like from
    # here. The fate is the window's to reason about, and it does, rather than
    # being claimed by a run that cannot see it.
    context "when the tool answers before anything can reach it" do
      let(:tool) { quick }

      it "leaves the reactor usable" do
        sibling = task_for(quick)
        error = react do
          task.wait
          sibling.spawn
          sibling.wait
        end
        expect(error).to be_nil
      end
    end
  end

  ##
  # A cancel arrives on the thread the scheduler runs on here, so this is also
  # the example for a canceller that must not block it: the sleep below is
  # reached only if `interrupt!` returned, and a canceller that waited for
  # the call to start would never get there.
  describe "a cancel that arrives while the call runs" do
    let(:task) { task_for(holding) }

    it "raises at the tool" do
      expect(react do
        task.spawn
        task.interrupt!
        ##
        # The reactor's turn: the scheduler delivers the raise when this
        # thread lets it, and a read before that would block the thread the
        # reactor runs on.
        sleep 0.1
        task.wait
      end).to be_a(LLM::Interrupt)
    end
  end

  ##
  # A cancel after the call has returned has nothing to interrupt, and the
  # fiber a task ran in has gone with it.
  describe "a cancel that arrives after the call has returned" do
    let(:task) { task_for(quick) }

    it "is a no-op" do
      cancelled = nil
      error = react do
        task.wait
        cancelled = task.interrupt!
      end
      expect([error, cancelled]).to eq([nil, nil])
    end

    ##
    # The second wait is answered from what the first one took, which is what
    # `Thread#value` does for the other in-process strategy.
    it "preserves the result" do
      first = second = nil
      react do
        first = task.wait
        task.interrupt!
        second = task.wait
      end
      expect(second.equal?(first)).to be(true)
    end

    it "does not run the hook" do
      react { task.wait }
      task.interrupt!
      expect(log).to be_empty
    end
  end

  ##
  # A group cancels its tasks in turn, and a task that has not been spawned is
  # one of them; the group's file has the rest of that story.
  describe "a cancel for a group whose tasks have not been spawned" do
    let(:task) { task_for(holding) }
    let(:group) { LLM::Function::Fiber::Group.new([task]) }

    before { group.interrupt! }

    it "reaches the task" do
      expect(react { group.wait }).to be_a(LLM::Interrupt)
    end
  end
end
