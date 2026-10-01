# frozen_string_literal: true

require "setup"
require "timeout"

##
# A turn is a loop, and between two of its requests there is nothing in
# flight to close and nothing running to raise into - so a cancel that
# arrived there reached nothing at all, until the loop named the caller it is
# running under and the caller learned to answer `interrupt!`.
#
# Every wait here has a deadline, so a hook that never fires is a failing
# example rather than a suite that stops where the hook was expected.
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

  ##
  # The phase the caller ends, announced by `LLM::Agent::Interrupt` before it
  # raises - the same hook the tool phase is announced through.
  def on_interrupt(scope: nil)
    @arrived << [:interrupt, scope]
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
  let(:model) { "gpt-5.4" }
  let(:payload) { {choices: [{message: {role: "assistant", content: "hi"}}]} }

  let(:transport) do
    double("transport",
      interrupt_errors: [],
      interrupted?: false,
      interrupt!: nil)
  end

  ##
  # The response the transport answers with, as a pair rather than a value.
  #
  # `handle_response` parses the body and writes the parsed result back
  # through the same reader, so a stub that always answered the raw string
  # would hand the adapter a String where it expects a completion. The
  # wrapper delegates both to this object, so the pair is what the parse
  # round trips through.
  let(:response) do
    Net::HTTPOK.new("1.1", "200", "OK").tap do |res|
      body = LLM.json.dump(payload)
      allow(res).to receive(:[]) { "application/json" }
      allow(res).to receive(:body) { body }
      allow(res).to receive(:body=) { |value| body = value }
    end
  end

  ##
  # What the loop tells the example, and what it waits on. The example holds
  # the gate closed until it has cancelled, so the loop is provably inside
  # the window when the interrupt is made.
  let(:arrived) { Queue.new }
  let(:gate) { Queue.new }
  let(:requests) { [] }
  let(:failing) { false }

  ##
  # The chat completions API, because the body the transport answers with is
  # a chat completion, and OpenAI defaults to the responses API.
  let(:agent) { LLM::Agent.new(provider, model:, mode: :completions) }
  let(:ctx) { agent.instance_variable_get(:@ctx) }

  before do
    fails = 0
    allow(provider).to receive(:transport).and_return(transport)
    ##
    # Answered where the real transport answers it, so the caller's fiber is
    # the turn's rather than this example's.
    allow(transport).to receive(:request_owner) { Fiber.current }
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
  # the caller is a thread that is not the one asking for the interrupt.
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
      LLM::Agent.new(provider, model:, mode: :completions,
                     tracer: BlockingTracer.new(provider, arrived:, gate:))
    end
    let(:caller) { ctx.instance_variable_get(:@caller) }

    context "while the loop is between two requests" do
      before do
        turn
        settle(arrived)
      end

      it "names the turn's thread as the caller's thread" do
        expect(caller.thread).to be(turn)
      end

      it "names the turn's fiber as the caller's fiber" do
        expect(caller.fiber).to be_a(Fiber)
      end
    end

    context "when the cancel arrives there" do
      before do
        turn
        settle(arrived)
        agent.interrupt!
      end

      it "ends the turn, though nothing is in flight" do
        expect(within { turn.value }).to be_a(LLM::Interrupt)
      end

      context "once the turn is over" do
        before { within { turn.value } }

        it "tells the tracer which phase ended" do
          expect(settle(arrived)).to eq([:interrupt, :agent])
        end

        it "makes no request of its own" do
          expect(requests.size).to eq(1)
        end

        it "leaves no caller behind" do
          expect(ctx.instance_variable_get(:@caller)).to be_nil
        end
      end
    end
  end

  describe "when the cancel arrives before the first request" do
    let(:agent) do
      LLM::Agent.new(provider, model:, mode: :completions,
                     compactor: BlockingCompactor,
                     compactor_options: {arrived:, gate:})
    end

    before do
      turn
      settle(arrived)
      agent.interrupt!
    end

    it "ends the turn" do
      expect(within { turn.value }).to be_a(LLM::Interrupt)
    end

    context "once the turn is over" do
      before { within { turn.value } }

      it "makes no request at all" do
        expect(requests).to be_empty
      end
    end
  end

  describe "when the cancel arrives while a retry is being waited out" do
    let(:failing) { true }
    let(:agent) do
      LLM::Agent.new(provider, model:, mode: :completions,
                     stream: BlockingRetry.new(arrived:, gate:),
                     retry_budget: 1)
    end

    before do
      turn
      settle(arrived)
      agent.interrupt!
    end

    it "ends the turn" do
      expect(within { turn.value }).to be_a(LLM::Interrupt)
    end

    context "once the turn is over" do
      before { within { turn.value } }

      it "makes no next attempt" do
        expect(requests.size).to eq(1)
      end
    end
  end

  ##
  # What a caller does with the names it holds, without a turn: the record is
  # built here the way `run_loop` builds it, and the context is asked to
  # cancel.
  describe "when the cancel comes from the turn's own thread" do
    let(:context) { LLM::Context.new(provider) }
    let(:ended) { [] }
    let(:scheduler) { nil }
    let(:fiber) do
      ended = self.ended
      Fiber.new do
        Fiber.yield
      rescue LLM::Interrupt => ex
        ended << ex
      end
    end
    let(:caller) do
      LLM::Object.from(
        thread: Thread.current,
        fiber:,
        scheduler:
      ).extend(LLM::Agent::Interrupt)
    end

    before do
      fiber.resume
      context.instance_variable_set(:@caller, caller)
      context.interrupt!
    end

    it "raises into the fiber rather than into the canceller" do
      expect(ended.first).to be_a(LLM::Interrupt)
    end

    context "when the fiber belongs to a scheduler" do
      let(:scheduler) { double("scheduler", fiber_interrupt: nil) }

      it "asks the scheduler rather than raising at the fiber" do
        expect(scheduler).to have_received(:fiber_interrupt)
          .with(fiber, kind_of(LLM::Interrupt))
      end
    end
  end

  ##
  # And the turn that never named a caller - a raw context, which has no loop
  # of its own - keeps the behaviour it had.
  describe "when no caller was recorded" do
    it "does not raise into the canceller" do
      expect { LLM::Context.new(provider).interrupt! }.not_to raise_error
    end
  end
end
