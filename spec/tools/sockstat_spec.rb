# frozen_string_literal: true

require "setup"
require "llm/tools/bsd"

RSpec.describe LLM::Tool::BSD::SockStat do
  let(:tool) { described_class.new }
  let(:result) { {ok: true, stdout: "USER COMMAND PID FD PROTO LOCAL ADDRESS\n", stderr: ""} }

  before do
    allow(tool).to receive(:exec).and_return(result)
  end

  describe ".function" do
    let(:params) { described_class.function.params }

    it "defines every param a listing takes" do
      expect(params.properties.keys).to contain_exactly(
        "family", "state", "ports", "protocols", "jail", "numeric",
        "wide", "quiet", "verbose", "timeout", "max_bytes"
      )
    end

    it "defines numeric, wide, quiet and verbose as booleans" do
      expect(params.properties[:numeric]).to be_a(LLM::Schema::Boolean)
      expect(params.properties[:wide]).to be_a(LLM::Schema::Boolean)
      expect(params.properties[:quiet]).to be_a(LLM::Schema::Boolean)
      expect(params.properties[:verbose]).to be_a(LLM::Schema::Boolean)
    end

    it "defaults the timeout to 10 seconds" do
      expect(params.properties[:timeout].default).to eq(10)
    end
  end

  describe "#call" do
    it "lists every socket with no flags" do
      tool.call
      expect(tool).to have_received(:exec).with(
        command: "sockstat",
        arguments: [],
        timeout: 10,
        max_bytes: described_class.max_bytes
      )
    end

    it "passes the family as -4" do
      tool.call(family: "inet")
      expect(tool).to have_received(:exec).with(hash_including(arguments: ["-4"]))
    end

    it "passes the family as -6" do
      tool.call(family: "inet6")
      expect(tool).to have_received(:exec).with(hash_including(arguments: ["-6"]))
    end

    it "passes the family as -u" do
      tool.call(family: "local")
      expect(tool).to have_received(:exec).with(hash_including(arguments: ["-u"]))
    end

    it "passes listening as -l" do
      tool.call(state: "listening")
      expect(tool).to have_received(:exec).with(hash_including(arguments: ["-l"]))
    end

    it "passes connected as -c" do
      tool.call(state: "connected")
      expect(tool).to have_received(:exec).with(hash_including(arguments: ["-c"]))
    end

    it "passes the jail as -j" do
      tool.call(jail: "www")
      expect(tool).to have_received(:exec).with(hash_including(arguments: ["-j", "www"]))
    end

    it "joins the ports into one -p" do
      tool.call(ports: %w[22 80 8000-8100])
      expect(tool).to have_received(:exec)
        .with(hash_including(arguments: ["-p", "22,80,8000-8100"]))
    end

    it "joins the protocols into one -P" do
      tool.call(protocols: %w[tcp udp])
      expect(tool).to have_received(:exec)
        .with(hash_including(arguments: ["-P", "tcp,udp"]))
    end

    it "passes numeric as -n" do
      tool.call(numeric: true)
      expect(tool).to have_received(:exec).with(hash_including(arguments: ["-n"]))
    end

    it "passes wide as -w" do
      tool.call(wide: true)
      expect(tool).to have_received(:exec).with(hash_including(arguments: ["-w"]))
    end

    it "passes quiet as -q" do
      tool.call(quiet: true)
      expect(tool).to have_received(:exec).with(hash_including(arguments: ["-q"]))
    end

    it "passes verbose as -v" do
      tool.call(verbose: true)
      expect(tool).to have_received(:exec).with(hash_including(arguments: ["-v"]))
    end

    it "passes every argument in a fixed order" do
      arguments = ["-4", "-l", "-j", "www", "-p", "22", "-P", "tcp", "-n", "-w", "-q", "-v"]
      tool.call(
        family: "inet", state: "listening", jail: "www", ports: ["22"],
        protocols: ["tcp"], numeric: true, wide: true, quiet: true, verbose: true
      )
      expect(tool).to have_received(:exec).with(hash_including(arguments:))
    end

    it "forwards the timeout" do
      tool.call(timeout: 5)
      expect(tool).to have_received(:exec).with(hash_including(timeout: 5))
    end

    it "passes the max bytes" do
      tool.call(max_bytes: 100)
      expect(tool).to have_received(:exec).with(hash_including(max_bytes: 100))
    end

    it "returns the result as it is" do
      expect(tool.call).to eq(result)
    end
  end

  describe "validation" do
    it "raises when the family is not one of the three" do
      expect { tool.call(family: "inet4") }
        .to raise_error("family must be one of: inet, inet6, local")
    end

    it "raises when the state is neither listening nor connected" do
      expect { tool.call(state: "bound") }
        .to raise_error("state must be one of: listening, connected")
    end

    it "raises when a port is not a number or a range" do
      expect { tool.call(ports: ["http"]) }
        .to raise_error("a port must be a number or a range, eg 22 or 8000-8100")
    end

    it "raises when a range has no end" do
      expect { tool.call(ports: ["8000-"]) }
        .to raise_error("a port must be a number or a range, eg 22 or 8000-8100")
    end

    it "raises when a protocol is not a name" do
      expect { tool.call(protocols: ["tcp,udp"]) }
        .to raise_error("a protocol must be a name, eg tcp or udp")
    end

    it "raises when the jail is empty" do
      expect { tool.call(jail: "") }
        .to raise_error("jail can't be empty")
    end

    it "raises when the jail begins with a dash" do
      expect { tool.call(jail: "-4") }
        .to raise_error("a jail can't begin with '-'")
    end
  end
end
