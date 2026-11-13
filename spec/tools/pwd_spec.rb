# frozen_string_literal: true

require "setup"
require "llm/tools/unix"

RSpec.describe LLM::Tool::Unix::Pwd do
  let(:tool) { described_class.new }
  let(:result) { {ok: true, stdout: "/usr/home/bart\n", stderr: ""} }

  before do
    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:[]).with("PWD").and_return(nil)
    allow(tool).to receive(:exec).and_return(result)
  end

  describe ".function" do
    let(:params) { described_class.function.params }

    it "defines the physical param" do
      expect(params.properties[:physical]).to be_a(LLM::Schema::Boolean)
    end

    it "defaults physical to false" do
      expect(params.properties[:physical].default).to eq(false)
    end
  end

  describe "#call" do
    it "runs pwd -L through #exec by default" do
      tool.call
      expect(tool).to have_received(:exec).with(
        command: "pwd",
        arguments: ["-L"],
        env: {},
        max_bytes: described_class.max_bytes
      )
    end

    it "runs pwd -P when physical is true" do
      tool.call(physical: true)
      expect(tool).to have_received(:exec)
        .with(hash_including(arguments: ["-P"]))
    end

    it "forwards PWD so -L can read the logical directory" do
      allow(ENV).to receive(:[]).with("PWD").and_return("/sys/kern")
      tool.call
      expect(tool).to have_received(:exec)
        .with(hash_including(env: {"PWD" => "/sys/kern"}))
    end

    it "does not forward PWD when it is not set" do
      tool.call
      expect(tool).to have_received(:exec).with(hash_including(env: {}))
    end

    it "passes the max bytes" do
      tool.call(max_bytes: 100)
      expect(tool).to have_received(:exec).with(hash_including(max_bytes: 100))
    end

    it "returns the result" do
      expect(tool.call).to eq(result)
    end
  end
end
