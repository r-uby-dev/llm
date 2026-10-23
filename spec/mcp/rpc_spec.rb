# frozen_string_literal: true

require "setup"

RSpec.describe LLM::MCP::RPC do
  let(:client) do
    Class.new do
      include LLM::MCP::RPC

      def initialize(timeout: 0.1)
        @timeout = timeout
      end
    end.new
  end

  let(:transport) do
    Class.new do
      attr_reader :writes

      def initialize(messages)
        @messages = messages.dup
        @writes = []
      end

      def write(message)
        @writes << message
      end

      def read_nonblock
        raise IO::EAGAINWaitReadable if @messages.empty?
        @messages.shift
      end
    end.new(messages)
  end

  describe "#call" do
    let(:messages) { [] }

    it "ignores notifications while waiting for the response" do
      messages.concat([
        {"jsonrpc" => "2.0", "method" => "notifications/message", "params" => {"level" => "info"}},
        {"jsonrpc" => "2.0", "id" => 0, "result" => {"ok" => true}}
      ])
      expect(client.call(transport, "ping")).to eq({"ok" => true})
    end

    it "raises when an unexpected response id arrives" do
      messages.concat([
        {"jsonrpc" => "2.0", "id" => 1, "result" => {"ok" => false}}
      ])
      expect { client.call(transport, "ping") }
        .to raise_error(LLM::MCP::MismatchError, /mismatched MCP response id 1/)
    end

    context "with concurrent callers" do
      let(:transport) do
        Class.new do
          attr_reader :writes

          def initialize
            @writes = []
            @messages = []
            @monitor = Monitor.new
          end

          def write(message)
            @monitor.synchronize do
              @writes << message
            end
          end

          def read_nonblock
            @monitor.synchronize do
              queue_responses if @messages.empty? && ready?
              raise IO::EAGAINWaitReadable if @messages.empty?
              @messages.shift
            end
          end

          private

          def ready?
            @writes.size == 2
          end

          def queue_responses
            @messages << response_for(@writes[1])
            @messages << response_for(@writes[0])
          end

          def response_for(message)
            {"jsonrpc" => "2.0", "id" => message[:id], "result" => {"ok" => message[:id]}}
          end
        end.new
      end
      let(:threads) do
        2.times.map do
          Thread.new { client.call(transport, "ping") }
        end
      end

      it "routes out-of-order responses to the waiting callers" do
        results = threads.map(&:value)
        expect(results).to contain_exactly({"ok" => 0}, {"ok" => 1})
      end

      it "assigns sequential request ids" do
        threads
        wait_until { transport.writes.size == 2 }
        expect(transport.writes.map { it[:id] }).to eq([0, 1])
        threads.each(&:value)
      end
    end
  end

  def wait_until(timeout: 1)
    start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    loop do
      return true if yield
      raise "condition not met" if Process.clock_gettime(Process::CLOCK_MONOTONIC) - start > timeout
      sleep 0.01
    end
  end
end
