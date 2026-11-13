# frozen_string_literal: true

require "setup"
require "llm/tools/unix"

RSpec.describe LLM::Tool::Unix::Mkdir do
  let(:tool) { described_class.new }
  let(:result) { {ok: true, stdout: "", stderr: ""} }

  before do
    allow(tool).to receive(:execute).and_return(result)
  end

  describe ".function" do
    let(:params) { described_class.function.params }

    it "defines the path param" do
      expect(params.properties[:path]).to be_a(LLM::Schema::String)
    end

    it "marks the path param as required" do
      expect(params.properties[:path]).to be_required
    end
  end

  describe "#call" do
    it "runs mkdir through #execute" do
      tool.call(path: "/tmp/new-dir")
      expect(tool).to have_received(:execute).with(
        command: "mkdir",
        arguments: ["-p", "/tmp/new-dir"],
        max_bytes: described_class.max_bytes
      )
    end

    it "returns the result" do
      expect(tool.call(path: "/tmp/new-dir")).to eq(result)
    end
  end
end
