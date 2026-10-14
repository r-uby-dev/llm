# frozen_string_literal: true

require "setup"
require "timeout"

class BlockingTracer < LLM::Tracer
  attr_reader :interrupt_thread

  def initialize(llm, arrived:, gate:)
    super(llm)
    @arrived, @gate = arrived, gate
  end

  def on_request_start(operation:, model: nil, inputs: nil, request_id: nil)
    nil
  end

  def on_request_finish(operation:, res:, model: nil, span: nil, outputs: nil, metadata: nil, request_id: nil)
    @arrived << :finish
    @gate.pop
    nil
  end

  def on_request_error(ex:, span: nil, request_id: nil)
    nil
  end

  def on_interrupt(scope: nil)
    @interrupt_thread = Thread.current
    @arrived << [:interrupt, scope]
    nil
  end
end

class BlockingRetry < LLM::Stream
  def initialize(arrived:, gate:)
    @arrived, @gate = arrived, gate
  end

  def on_retry(_ex, _attempt)
    @arrived << :retry
    @gate.pop
  end
end

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

  let(:response) do
    Net::HTTPOK.new("1.1", "200", "OK").tap do |res|
      body = LLM.json.dump(payload)
      allow(res).to receive(:[]) { "application/json" }
      allow(res).to receive(:body) { body }
      allow(res).to receive(:body=) { |value| body = value }
    end
  end

  let(:arrived) { Queue.new }
  let(:gate) { Queue.new }
  let(:requests) { [] }
  let(:failing) { false }

  let(:agent) { LLM::Agent.new(provider, model:, mode: :completions) }
  let(:ctx) { agent.instance_variable_get(:@ctx) }

  before do
    fails = 0
    allow(provider).to receive(:transport).and_return(transport)
    allow(transport).to receive(:request_owner) { Fiber.current }
    allow(transport).to receive(:set_body_stream)
    allow(transport).to receive(:request) do |*|
      requests << :request
      raise Net::ReadTimeout if failing && (fails += 1) == 1
      response
    end
  end

  after do
    @turn&.kill
  end

  describe "when the cancel arrives between two requests" do
    let(:tracer) { BlockingTracer.new(provider, arrived:, gate:) }
    let(:agent) do
      LLM::Agent.new(provider, model:, mode: :completions, tracer:)
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

        it "announces from the turn's thread rather than the canceller's" do
          expect(tracer.interrupt_thread).to be(turn)
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

  describe "when no caller was recorded" do
    it "does not raise into the canceller" do
      expect { LLM::Context.new(provider).interrupt! }.not_to raise_error
    end
  end

  def settle(queue, timeout = 5)
    Timeout.timeout(timeout) { queue.pop }
  end

  def within(timeout = 5, &block)
    Timeout.timeout(timeout, &block)
  end

  def run_turn
    agent.talk("hi")
    nil
  rescue LLM::Interrupt => ex
    ex
  end

  def turn
    @turn ||= Thread.new { run_turn }
  end
end
