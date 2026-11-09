# frozen_string_literal: true

require "setup"
require "llm/tools/ruby"
require "llm/tools/exec"

RSpec.describe LLM::Tool::Ruby do
  let(:tool) { described_class.new }
  let(:shell) { instance_double(LLM::Tool::Exec) }
  let(:result) { {ok: true, stdout: "3\n", stderr: ""} }

  before do
    allow(LLM::Tool::Exec).to receive(:new).and_return(shell)
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
    before do
      allow(shell).to receive(:call).and_return(result)
    end

    it "runs ruby through a shell tool" do
      tool.call(code: "puts 1 + 2")
      expect(shell).to have_received(:call).with(
        command: RbConfig.ruby,
        arguments: ["-e", "puts 1 + 2"],
        timeout: 15,
        max_bytes: LLM::Tool::Exec.max_bytes
      )
    end

    it "returns the shell result" do
      expect(tool.call(code: "puts 1")).to eq(result)
    end

    it "forwards the timeout" do
      tool.call(code: "puts 1", timeout: 5)
      expect(shell).to have_received(:call).with(hash_including(timeout: 5))
    end
  end
end
