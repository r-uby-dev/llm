# frozen_string_literal: true

require "setup"
require "llm/tools/unix"

RSpec.describe LLM::Tool::Unix::Uname do
  let(:tool) { described_class.new }
  let(:result) { {ok: true, stdout: "FreeBSD\n", stderr: ""} }

  before do
    allow(tool).to receive(:exec).and_return(result)
  end

  describe ".function" do
    let(:params) { described_class.function.params }

    it "defines the POSIX params and nothing else" do
      expect(params.properties.keys).to contain_exactly(
        "kernel", "nodename", "release", "version", "machine", "all",
        "timeout", "max_bytes"
      )
    end

    it "defines every flag as a boolean" do
      expect(params.properties[:kernel]).to be_a(LLM::Schema::Boolean)
      expect(params.properties[:nodename]).to be_a(LLM::Schema::Boolean)
      expect(params.properties[:release]).to be_a(LLM::Schema::Boolean)
      expect(params.properties[:version]).to be_a(LLM::Schema::Boolean)
      expect(params.properties[:machine]).to be_a(LLM::Schema::Boolean)
      expect(params.properties[:all]).to be_a(LLM::Schema::Boolean)
    end
  end

  describe "#call" do
    it "passes no flag when none is asked for" do
      tool.call
      expect(tool).to have_received(:exec).with(
        command: "uname",
        arguments: [],
        timeout: 5,
        max_bytes: described_class.max_bytes
      )
    end

    it "passes kernel as -s" do
      tool.call(kernel: true)
      expect(tool).to have_received(:exec).with(hash_including(arguments: ["-s"]))
    end

    it "passes nodename as -n" do
      tool.call(nodename: true)
      expect(tool).to have_received(:exec).with(hash_including(arguments: ["-n"]))
    end

    it "passes release as -r" do
      tool.call(release: true)
      expect(tool).to have_received(:exec).with(hash_including(arguments: ["-r"]))
    end

    it "passes version as -v" do
      tool.call(version: true)
      expect(tool).to have_received(:exec).with(hash_including(arguments: ["-v"]))
    end

    it "passes machine as -m" do
      tool.call(machine: true)
      expect(tool).to have_received(:exec).with(hash_including(arguments: ["-m"]))
    end

    it "passes every flag in a fixed order" do
      tool.call(kernel: true, nodename: true, release: true, version: true, machine: true)
      expect(tool).to have_received(:exec)
        .with(hash_including(arguments: %w[-m -n -r -s -v]))
    end

    it "passes all as -a on its own" do
      tool.call(all: true, kernel: true, machine: true)
      expect(tool).to have_received(:exec).with(hash_including(arguments: ["-a"]))
    end

    it "forwards the timeout" do
      tool.call(timeout: 9)
      expect(tool).to have_received(:exec).with(hash_including(timeout: 9))
    end

    it "passes the max bytes" do
      tool.call(max_bytes: 100)
      expect(tool).to have_received(:exec).with(hash_including(max_bytes: 100))
    end

    it "returns the result as it is" do
      expect(tool.call).to eq(result)
    end
  end
end
