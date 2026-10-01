# frozen_string_literal: true

require "setup"
require "timeout"

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
# Every wait here has a deadline. A hook that never fires is a failure the
# suite can report rather than a suite that stops where the hook was
# expected - which is the convention the task specs set for cancels, and it
# is what turned each of this file's three drafts into a named failure.
class BlockingTracer < LLM::Tracer
  def initialize(llm, arrived:, gate:)
    super(llm)
    @arrived, @gate = arrived, gate
  end

  def on_request_start(operation:, model: nil, inputs: nil, request_id: nil)
    nil
  end

  ##
  # The end of a request, which is the window itself: the provider has
  # answered, the transport has taken the request out of its map, and no
  # tool is running. The example is told the loop is there, and the loop
  # waits to be cancelled.
  #
  # A tracer rather than a stream, because a stream would put the response
  # through the streaming path and this example is about the turn between
  # two requests, not about how a response arrives.
  def on_request_finish(operation:, res:, model: nil, span: nil, outputs: nil, metadata: nil, request_id: nil)
    @arrived << :finish
    @gate.pop
    nil
  end

  def on_request_error(ex:, span: nil, request_id: nil)
    nil
  end
end

##
# The same window, on the path a retry opens: the request that was made
# failed and the next one has not been, so there is nothing in flight and
# nothing running. A retry is announced before the backoff, so a stream is
# the interface for it and no response is parsed to reach it.
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

  ##
  # The response the transport answers with, as a pair rather than a value.
  #
  # `handle_response` parses the body and writes the parsed result back
  # through the same reader, so a stub that always answered the raw string
  # would hand the adapter a String where it expects a completion - which
  # is what this file did, and what made the one example that let a turn
  # finish fail with `undefined method 'choices' for an instance of
  # String`. The wrapper delegates both to this object, so the pair is what
  # the parse actually round trips through.
  let(:response) do
    Net::HTTPOK.new("1.1", "200", "OK").tap do |res|
      body = LLM.json.dump(payload)
      allow(res).to receive(:[]) { "application/json" }
      allow(res).to receive(:body) { body }
      allow(res).to receive(:body=) { |value| body = value }
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

  ##
  # The chat completions API, because the body the transport answers with
  # is a chat completion. OpenAI defaults to the responses API, and these
  # examples are about the loop rather than about which API it drove.
  let(:agent) { LLM::Agent.new(provider, model: "gpt-5.4", mode: :completions) }
  let(:ctx) { agent.instance_variable_get(:@ctx) }

  before do
    ##
    # Built on this thread rather than on a turn's, so the example and its
    # turn share one agent, one observer, and one pair of queues.
    agent
    arrived
    gate
    fails = 0
    allow(provider).to receive(:transport).and_return(transport)
    allow(transport).to receive(:set_body_stream)
    allow(transport).to receive(:request) do |*|
      requests << :request
      raise Net::ReadTimeout if failing && (fails += 1) == 1
      response
    end
  end

  after do
    ##
    # A turn that is still waiting would outlive the stubs this example
    # installed, and its next call would be a real one.
    @turn&.kill
  end

  ##
  # A queue read that cannot wait forever.
  def settle(queue, timeout = 5)
    Timeout.timeout(timeout) { queue.pop }
  end

  ##
  # And the same for anything else that might not come back.
  def within(timeout = 5, &block)
    Timeout.timeout(timeout, &block)
  end

  ##
  # The turn, on a thread of its own, which is what a cancel has to reach:
  # the frame is a thread that is not the one asking for the interrupt.
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
      LLM::Agent.new(provider, model: "gpt-5.4", mode: :completions,
                     tracer: BlockingTracer.new(provider, arrived:, gate:))
    end

    ##
    # The frame is what a cancel is delivered to, and it is the thread the
    # turn is on - not the thread that started it, and not the fiber the
    # request was made on, which has no request left to close.
    it "records the frame the turn is running in" do
      turn
      expect(settle(arrived)).to eq(:finish)
      expect(ctx.turn_thread).to be(turn)
      gate << :go
      expect(within { turn.value }).to be_nil
    end

    it "ends the turn, though nothing is in flight" do
      turn
      expect(settle(arrived)).to eq(:finish)
      agent.interrupt!
      expect(within { turn.value }).to be_a(LLM::Interrupt)
    end

    ##
    # A raise, and not a second request: the turn ends where it is rather
    # than carrying on to ask the model something nobody is waiting for.
    it "makes no request of its own" do
      turn
      settle(arrived)
      agent.interrupt!
      within { turn.value }
      expect(requests.size).to eq(1)
    end

    it "leaves no frame behind once the turn is over" do
      turn
      settle(arrived)
      agent.interrupt!
      within { turn.value }
      expect(ctx.turn_thread).to be_nil
      expect(ctx.turn_owner).to be_nil
    end
  end

  describe "when the cancel arrives before the first request" do
    let(:agent) do
      LLM::Agent.new(provider, model: "gpt-5.4", mode: :completions,
                     compactor: BlockingCompactor,
                     compactor_options: {arrived:, gate:})
    end

    it "ends the turn without making a request" do
      turn
      expect(settle(arrived)).to eq(:compaction)
      agent.interrupt!
      expect(within { turn.value }).to be_a(LLM::Interrupt)
      expect(requests).to be_empty
    end
  end

  describe "when the cancel arrives while a retry is being waited out" do
    let(:failing) { true }
    let(:agent) do
      LLM::Agent.new(provider, model: "gpt-5.4", mode: :completions,
                     stream: BlockingRetry.new(arrived:, gate:),
                     retry_budget: 1)
    end

    ##
    # The retry is what a cancel used to be lost to: the request that
    # failed is not in flight any more, the one that follows has not been
    # made, and the backoff sleeps in between.
    it "ends the turn without making the next attempt" do
      turn
      expect(settle(arrived)).to eq(:retry)
      agent.interrupt!
      expect(within { turn.value }).to be_a(LLM::Interrupt)
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
