# frozen_string_literal: true

require "setup"

##
# The window a turn has nothing in it.
#
# `Context#interrupt!` reaches a request in flight - the transport closes
# the socket of the request registered under the owner - and a tool that is
# running, which is a task that can be raised into. Both are bound to a
# phase, so between them a cancel reached nothing at all: the loop is
# between two requests, or waiting out a retry, or building the next one.
#
# `LLM::Agent#run_loop` records the thread and the fiber it is running on
# for as long as the turn lasts, and an interrupt that has nothing more
# precise to do is raised into that frame.
#
# Every example here runs the turn on a thread of its own, because that is
# the shape the window is closed for: a worker runs the turn, a cancel
# arrives on another thread, and the raise has to land where the turn is.
class BlockingStep < LLM::Stream
  def initialize(arrived:, gate:)
    @arrived, @gate = arrived, gate
  end

  ##
  # The boundary between one request and the next, which is the window
  # itself: the response is in the conversation, the transport has taken
  # the request out of its map, and no tool is running. The example is
  # told the loop is there, and the loop waits to be cancelled.
  def on_step(_ctx, _res)
    @arrived << :step
    @gate.pop
  end
end

##
# The same window, on the path a retry opens: the request that was made
# failed and the next one has not been, so there is nothing in flight and
# nothing running.
class BlockingRetry < LLM::Stream
  def initialize(arrived:, gate:)
    @arrived, @gate = arrived, gate
  end

  def on_retry(_ex, _attempt)
    @arrived << :retry
    @gate.pop
  end
end

##
# And the window before any request was made. A compactor runs at the top
# of `Context#talk`, before a prompt is built and before the transport is
# asked for anything, so a turn cancelled here has nothing at all in
# flight - which is the moment an application that offers a cancel from
# the first claim has to be able to honour.
class BlockingCompactor < LLM::Compactor
  def call(arrived:, gate:, **)
    arrived << :compaction
    gate.pop
  end
end

RSpec.describe "a turn interrupted between its requests" do
  let(:provider) { LLM.openai(key: "test") }
  let(:transport) do
    double("transport",
      request_owner: :owner,
      interrupt_errors: [],
      interrupted?: false,
      interrupt!: nil)
  end
  let(:payload) { {choices: [{message: {role: "assistant", content: "hi"}}]} }
  let(:response) do
    Net::HTTPOK.new("1.1", "200", "OK").tap do |res|
      allow(res).to receive(:body).and_return(LLM.json.dump(payload))
      allow(res).to receive(:[]).and_return("application/json")
    end
  end

  ##
  # What the loop tells the example, and what it waits on. The example
  # holds the gate closed until it has cancelled, so the cancel and the
  # loop cannot race: the loop is provably inside the window when the
  # interrupt is made.
  let(:arrived) { Queue.new }
  let(:gate) { Queue.new }
  let(:requests) { [] }
  let(:failing) { false }
  let(:agent) { LLM::Agent.new(provider, model: "gpt-5.4") }
  let(:ctx) { agent.instance_variable_get(:@ctx) }

  before do
    fails = 0
    allow(provider).to receive(:transport).and_return(transport)
    allow(transport).to receive(:set_body_stream)
    allow(transport).to receive(:request) do |*|
      requests << :request
      raise Net::ReadTimeout if failing && (fails += 1) == 1
      response
    end
  end

  ##
  # The turn, on a thread of its own. What a cancel has to reach is a
  # frame, so the example needs one that is not its own - and the thread
  # answers with the exception it ended on, or nil when the turn worked.
  def run_turn
    agent.talk("hi")
    nil
  rescue LLM::Interrupt => ex
    ex
  end

  def turn
    @turn ||= Thread.new { run_turn }
  end

  describe "when the cancel arrives between two requests" do
    let(:agent) do
      LLM::Agent.new(provider, model: "gpt-5.4", stream: BlockingStep.new(arrived:, gate:))
    end

    ##
    # The frame is what a cancel is delivered to, and it is the thread the
    # turn is on - not the thread that started it, and not the fiber the
    # request was made on, which no longer has a request to close.
    it "records the frame the turn is running in" do
      turn
      expect(arrived.pop).to eq(:step)
      expect(ctx.turn_thread).to be(turn)
      gate << :go
      expect(turn.join(5)).to be(turn)
    end

    it "ends the turn, though nothing is in flight" do
      turn
      expect(arrived.pop).to eq(:step)
      agent.interrupt!
      expect(turn.join(5)).to be(turn)
      expect(turn.value).to be_a(LLM::Interrupt)
    end

    ##
    # A raise, and not a second request: the turn ends where it is rather
    # than carrying on to ask the model something nobody is waiting for.
    it "makes no request of its own" do
      turn
      arrived.pop
      agent.interrupt!
      turn.join(5)
      expect(requests.size).to eq(1)
    end

    it "leaves no frame behind once the turn is over" do
      turn
      arrived.pop
      agent.interrupt!
      turn.join(5)
      expect(ctx.turn_thread).to be_nil
      expect(ctx.turn_owner).to be_nil
    end
  end

  describe "when the cancel arrives before the first request" do
    let(:agent) do
      LLM::Agent.new(provider, model: "gpt-5.4",
                     compactor: BlockingCompactor,
                     compactor_options: {arrived:, gate:})
    end

    it "ends the turn without making a request" do
      turn
      expect(arrived.pop).to eq(:compaction)
      agent.interrupt!
      expect(turn.join(5)).to be(turn)
      expect(turn.value).to be_a(LLM::Interrupt)
      expect(requests).to be_empty
    end
  end

  describe "when the cancel arrives while a retry is being waited out" do
    let(:failing) { true }
    let(:agent) do
      LLM::Agent.new(provider, model: "gpt-5.4",
                     stream: BlockingRetry.new(arrived:, gate:),
                     retry_budget: 1)
    end

    ##
    # The retry is what a cancel used to be lost to: the request that
    # failed is not in flight any more, the one that follows has not been
    # made, and the backoff sleeps in between.
    it "ends the turn without making the next attempt" do
      turn
      expect(arrived.pop).to eq(:retry)
      agent.interrupt!
      expect(turn.join(5)).to be(turn)
      expect(turn.value).to be_a(LLM::Interrupt)
      expect(requests.size).to eq(1)
    end
  end

  ##
  # A cancel from the turn's own thread, which is a fiber of a reactor.
  #
  # The thread is the canceller here, so the raise cannot go through it -
  # it has to go through the fiber the turn is running on, or the
  # interrupt would land in whoever asked for it.
  describe "when the cancel comes from the turn's own thread" do
    it "raises into the fiber rather than into the canceller" do
      context = LLM::Context.new(provider)
      ended = nil
      fiber = Fiber.new do
        Fiber.yield
      rescue LLM::Interrupt => ex
        ended = ex
      end
      fiber.resume
      context.turn_thread = Thread.current
      context.turn_owner = fiber
      context.interrupt!
      expect(ended).to be_a(LLM::Interrupt)
    end
  end

  ##
  # And the turn that never recorded a frame - a raw context, which has
  # no loop of its own - keeps the behaviour it had: a cancel with
  # nothing to interrupt is a cancel that does nothing, rather than one
  # raised into the caller.
  describe "when no frame was recorded" do
    it "does not raise into the canceller" do
      expect { LLM::Context.new(provider).interrupt! }.not_to raise_error
    end
  end
end
