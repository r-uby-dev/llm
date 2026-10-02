# frozen_string_literal: true

require "setup"

RSpec.describe LLM::Provider do
  context "with openai" do
    let(:provider) { LLM.openai(key: ENV["OPENAI_SECRET"]) }

    context "when given the with method" do
      subject { provider.send(:headers) }

      before do
        provider
          .with(headers: {"OpenAI-Organization" => "llmrb"})
          .with(headers: {"OpenAI-Project" => "llmrb/llm"})
      end

      it "adds headers via the legacy headers: keyword" do
        is_expected.to include(
          "OpenAI-Organization" => "llmrb",
          "OpenAI-Project" => "llmrb/llm"
        )
      end

      context "when given a positional header hash" do
        before { provider.with("User-Agent" => "llmrb/1.0") }

        it "adds the header" do
          is_expected.to include("User-Agent" => "llmrb/1.0")
        end
      end

      context "when combining positional and keyword headers" do
        before do
          provider.with("User-Agent" => "llmrb/1.0", :headers => {"X-Extra" => "yes"})
        end

        it "merges both forms" do
          is_expected.to include("User-Agent" => "llmrb/1.0", "X-Extra" => "yes")
        end
      end
    end

    context "when given the with method with a block" do
      let(:scoped) { {} }

      before do
        provider.with("x-session-id" => "abc") { scoped.replace(provider.send(:headers)) }
      end

      it "adds the header for the duration of the block" do
        expect(scoped).to include("x-session-id" => "abc")
      end

      it "restores the previous headers after the block" do
        expect(provider.send(:headers)).not_to include("x-session-id" => "abc")
      end
    end

    context "when scoped headers encounter garbage collection" do
      it "retains the header until its scope ends" do
        provider.with("x-session-id" => "abc") do
          GC.start
          expect(provider.send(:headers)).to include("x-session-id" => "abc")
        end
        expect(provider.send(:headers)).not_to have_key("x-session-id")
      end

      it "retains nested headers and restores the outer scope" do
        provider.with("x-session-id" => "outer", "X-Outer" => "yes") do
          provider.with("x-session-id" => "inner") do
            GC.start
            expect(provider.send(:headers)).to include("x-session-id" => "inner", "X-Outer" => "yes")
          end
          GC.start
          expect(provider.send(:headers)).to include("x-session-id" => "outer", "X-Outer" => "yes")
        end
      end

      it "restores a surviving outer scope after an inner scope raises" do
        provider.with("x-session-id" => "outer") do
          expect do
            provider.with("x-session-id" => "inner") do
              GC.start
              expect(provider.send(:headers)).to include("x-session-id" => "inner")
              raise "boom"
            end
          end.to raise_error(RuntimeError, "boom")
          GC.start
          expect(provider.send(:headers)).to include("x-session-id" => "outer")
        end
        expect(provider.send(:headers)).not_to have_key("x-session-id")
      end
    end

    context "when a scoped header block raises" do
      before do
        provider.with("x-session-id" => "abc") { raise "boom" }
      rescue RuntimeError
      end

      it "restores the previous headers" do
        expect(provider.send(:headers)).not_to include("x-session-id" => "abc")
      end
    end

    context "when a scoped header is set while another fiber reads" do
      let(:other) { Thread.new { provider.send(:headers) } }

      before do
        provider.with("x-session-id" => "abc") { other.value }
      end

      it "does not leak the header to the other fiber" do
        expect(other.value).not_to include("x-session-id" => "abc")
      end
    end

    describe "#key?" do
      context "when given a key resolved via environment" do
        let(:key) { "sk-from-env" }
        before { ENV["OPENAI_API_KEY"] = key }
        after { ENV.delete("OPENAI_API_KEY")  }
        subject { LLM.openai.key? }
        it { is_expected.to be(true) }
      end

      context "when given an empty string as a key" do
        subject { LLM.openai(key: "    ").key? }
        it { is_expected.to be(false) }
      end

      context "when given an API key" do
        subject { LLM.openai(key: "sk-12345").key? }
        it { is_expected.to be(true) }
      end
    end
  end

  context "with bedrock" do
    subject(:provider) do
      LLM.bedrock(
        access_key_id: "AKIA_TEST",
        secret_access_key: "SECRET",
        region: "us-east-1"
      )
    end

    it "builds a Bedrock provider" do
      expect(provider).to be_a(LLM::Bedrock)
      expect(provider.name).to eq(:bedrock)
    end

    context "when credentials are resolved from the environment" do
      let(:access_key_id) { "AKIA_ENV" }
      let(:secret_access_key) { "SECRET_ENV" }
      let(:region) { "eu-west-1" }

      before do
        ENV["AWS_ACCESS_KEY_ID"] = access_key_id
        ENV["AWS_SECRET_ACCESS_KEY"] = secret_access_key
        ENV["AWS_REGION"] = region
      end
      after do
        ENV.delete("AWS_ACCESS_KEY_ID")
        ENV.delete("AWS_SECRET_ACCESS_KEY")
        ENV.delete("AWS_REGION")
      end

      subject { LLM.bedrock.key? }
      it { is_expected.to be(true) }
    end

    context "when credentials are missing" do
      before do
        ENV.delete("AWS_ACCESS_KEY_ID")
        ENV.delete("AWS_SECRET_ACCESS_KEY")
      end
      after do
        ENV.delete("AWS_ACCESS_KEY_ID")
        ENV.delete("AWS_SECRET_ACCESS_KEY")
      end

      it "raises an ArgumentError" do
        expect { LLM.bedrock }.to raise_error(ArgumentError, "you must provide an API key")
      end
    end
  end

  context "with a transport class" do
    it "builds a transport from the provider settings" do
      provider = LLM.openai(key: "test", transport: LLM::Transport.net_http_persistent)
      expect(provider.send(:transport)).to be_a(LLM::Transport::PersistentHTTP)
    end
  end

  context "#interrupt!" do
    let(:provider) { LLM.openai(key: "test") }
    let(:owner) { Fiber.current }

    it "finishes an active transient request" do
      http = Net::HTTP.new("example.com")
      allow(http).to receive(:active?).and_return(true)
      allow(http).to receive(:finish)
      req = LLM::Transport::HTTP::ActiveRequest.new(client: http)
      provider.send(:transport).send(:set_request, req, owner)
      provider.interrupt!(owner)
      expect(http).to have_received(:finish)
    end

    it "finishes an active persistent connection" do
      persistent_class = if defined?(Net::HTTP::Persistent)
        Net::HTTP::Persistent
      else
        stub_const("Net::HTTP::Persistent", Class.new)
      end
      transport = LLM::Transport::PersistentHTTP.new(host: "api.openai.com", port: 443, timeout: 60, connect_timeout: 5, ssl: true)
      provider = LLM.openai(key: "test", transport:)
      client = persistent_class.allocate
      connection = double(:connection, http: nil)
      allow(client).to receive(:finish)
      req = LLM::Transport::PersistentHTTP::ActiveRequest.new(client:, connection:)
      provider.send(:transport).send(:set_request, req, owner)
      provider.interrupt!(owner)
      expect(client).to have_received(:finish).with(connection)
    end
  end

  describe "#with_tracer" do
    let(:provider) { LLM.openai(key: "test") }
    let(:events) { [] }
    let(:tracer) do
      events = self.events
      Class.new(LLM::Tracer::Null) do
        define_method(:on_exit) { events << :exit }
      end.new(provider)
    end
    let(:gate) { Queue.new }
    let(:opened) { Queue.new }

    context "when the same tracer is scoped twice" do
      before do
        provider.with_tracer(tracer) do
          provider.with_tracer(tracer) { events << :inner }
        end
      end

      it "ends the tracer once, on the way out of the outermost scope" do
        expect(events).to eq([:inner, :exit])
      end
    end

    context "when the tracer is scoped for a second turn" do
      before do
        provider.with_tracer(tracer) { events << :first }
        provider.with_tracer(tracer) { events << :second }
      end

      it "ends the tracer once per turn" do
        expect(events).to eq([:first, :exit, :second, :exit])
      end
    end

    context "when a scope is opened on another thread" do
      before do
        provider.with_tracer(tracer) do
          Thread.new { provider.with_tracer(tracer) { events << :other_thread } }.join
          events << :outer
        end
      end

      it "ends the tracer after the outer scope, not the other thread's" do
        expect(events).to eq([:other_thread, :outer, :exit])
      end
    end

    context "when the outer scope exits before the other thread's" do
      before do
        thread = Thread.new do
          provider.with_tracer(tracer) do
            ##
            # The scope is open before the thread holds it: the outer
            # scope below must be the one that ends it, or neither.
            opened << :open
            gate.pop
            events << :other_thread
          end
        end
        opened.pop
        provider.with_tracer(tracer) { events << :outer }
        gate << :go
        thread.join
      end

      it "ends the tracer when the last scope exits" do
        expect(events).to eq([:outer, :other_thread, :exit])
      end
    end
  end

  describe "#retry_budget" do
    context "with openai" do
      let(:provider) { LLM.openai(key: "test") }

      it "returns the default budget" do
        expect(provider.retry_budget).to eq(5)
      end
    end

    context "with alibaba" do
      let(:provider) { LLM.alibaba(key: "test") }

      it "returns a higher budget" do
        expect(provider.retry_budget).to eq(8)
      end
    end
  end
end
