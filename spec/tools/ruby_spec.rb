# frozen_string_literal: true

require "setup"
require "llm/tools/ruby"
require "llm/tools/ruby"

RSpec.describe LLM::Tool::Ruby do
  let(:tool) { described_class.new }
  let(:result) { {ok: true, stdout: "3\n", stderr: ""} }

  before do
    allow(tool).to receive(:exec).and_return(result)
  end

  describe ".function" do
    let(:params) { described_class.function.params }

    it "defines the code param" do
      expect(params.properties[:code]).to be_a(LLM::Schema::String)
    end

    it "marks the code param as required" do
      expect(params.properties[:code]).to be_required
    end
  end

  describe "#call" do
    it "runs ruby through #exec" do
      tool.call(code: "puts 1 + 2")
      expect(tool).to have_received(:exec).with(
        command: RbConfig.ruby,
        arguments: ["-e", "puts 1 + 2"],
        timeout: 15,
        max_bytes: described_class.max_bytes
      )
    end

    it "returns the result" do
      expect(tool.call(code: "puts 1")).to eq(result)
    end

    it "forwards the timeout" do
      tool.call(code: "puts 1", timeout: 5)
      expect(tool).to have_received(:exec).with(hash_including(timeout: 5))
    end
  end
end
