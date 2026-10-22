# frozen_string_literal: true

require "setup"

RSpec.describe LLM::Transport::Utils do
  describe ".resolve_transport" do
    let(:options) do
      {host: "api.example.com", port: 443, timeout: 240, connect_timeout: 5, ssl: true, persistent: false}
    end

    context "with :net_http" do
      subject(:transport) { described_class.resolve_transport(transport: :net_http, **options) }

      it "builds a Net::HTTP transport" do
        expect(transport).to be_a(LLM::Transport::HTTP)
      end
    end

    context "with :net_http_persistent" do
      subject(:transport) { described_class.resolve_transport(transport: :net_http_persistent, **options) }

      it "builds a persistent Net::HTTP transport" do
        expect(transport).to be_a(LLM::Transport::PersistentHTTP)
      end
    end

    context "with a transport that no longer exists" do
      subject(:transport) { described_class.resolve_transport(transport: :curb, **options) }

      it "raises an ArgumentError" do
        expect { transport }.to raise_error(ArgumentError, /unknown transport: :curb/)
      end

      it "names the transports that do exist" do
        expect { transport }.to raise_error(ArgumentError, /:net_http, :net_http_persistent/)
      end
    end
  end
end
