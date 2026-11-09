# frozen_string_literal: true

require "setup"
require "llm/tools/mkdir"
require "llm/tools/exec"

RSpec.describe LLM::Tool::Mkdir do
  let(:tool) { described_class.new }
  let(:shell) { instance_double(LLM::Tool::Exec) }
  let(:result) { {ok: true, stdout: "", stderr: ""} }

  before do
    allow(LLM::Tool::Exec).to receive(:new).and_return(shell)
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
    before do
      allow(shell).to receive(:call).and_return(result)
    end

    it "runs mkdir through the exec tool" do
      tool.call(path: "/tmp/new-dir")
      expect(shell).to have_received(:call).with(
        command: "mkdir",
        arguments: ["-p", "/tmp/new-dir"],
        max_bytes: LLM::Tool::Exec.max_bytes
      )
    end

    it "returns the exec result" do
      expect(tool.call(path: "/tmp/new-dir")).to eq(result)
    end
  end
end
