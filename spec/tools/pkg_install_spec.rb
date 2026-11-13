# frozen_string_literal: true

require "setup"
require "llm/tools/bsd"

RSpec.describe LLM::Tool::BSD::PkgInstall do
  let(:tool) { described_class.new }
  let(:result) { {ok: true, stdout: "Updating catalogue...\n", stderr: ""} }

  before do
    allow(tool).to receive(:execute).and_return(result)
  end

  describe ".function" do
    let(:params) { described_class.function.params }

    it "defines every param an install takes" do
      expect(params.properties.keys).to contain_exactly(
        "packages", "dry_run", "no_repo_update", "quiet", "force", "no_scripts",
        "automatic", "autoremove", "local_only", "match", "repositories",
        "timeout", "max_bytes"
      )
    end

    it "marks the packages param as required" do
      expect(params.properties[:packages]).to be_required
    end

    it "defines the flags as booleans" do
      expect(params.properties[:dry_run]).to be_a(LLM::Schema::Boolean)
      expect(params.properties[:autoremove]).to be_a(LLM::Schema::Boolean)
    end

    it "constrains the match to its values" do
      expect(params.properties[:match].enum).to eq(described_class::MATCHES.keys)
    end

    it "defaults the match to exact and the timeout to 300 seconds" do
      expect(params.properties[:match].default).to eq("exact")
      expect(params.properties[:timeout].default).to eq(300)
    end
  end

  describe "#call" do
    it "installs the package without a prompt" do
      tool.call(packages: ["zsh"])
      expect(tool).to have_received(:execute).with(
        command: "pkg",
        arguments: ["install", "-y", "zsh"],
        timeout: 300,
        max_bytes: described_class.max_bytes
      )
    end

    it "passes the packages in the order given" do
      tool.call(packages: %w[zsh git])
      expect(tool).to have_received(:execute)
        .with(hash_including(arguments: ["install", "-y", "zsh", "git"]))
    end

    it "passes dry_run as -n" do
      tool.call(packages: ["zsh"], dry_run: true)
      expect(tool).to have_received(:execute)
        .with(hash_including(arguments: ["install", "-n", "-y", "zsh"]))
    end

    it "passes no_repo_update as -U" do
      tool.call(packages: ["zsh"], no_repo_update: true)
      expect(tool).to have_received(:execute)
        .with(hash_including(arguments: ["install", "-U", "-y", "zsh"]))
    end

    it "passes quiet as -q" do
      tool.call(packages: ["zsh"], quiet: true)
      expect(tool).to have_received(:execute)
        .with(hash_including(arguments: ["install", "-q", "-y", "zsh"]))
    end

    it "passes force as -f" do
      tool.call(packages: ["zsh"], force: true)
      expect(tool).to have_received(:execute)
        .with(hash_including(arguments: ["install", "-f", "-y", "zsh"]))
    end

    it "passes no_scripts as -I" do
      tool.call(packages: ["zsh"], no_scripts: true)
      expect(tool).to have_received(:execute)
        .with(hash_including(arguments: ["install", "-I", "-y", "zsh"]))
    end

    it "passes automatic as -A" do
      tool.call(packages: ["zsh"], automatic: true)
      expect(tool).to have_received(:execute)
        .with(hash_including(arguments: ["install", "-A", "-y", "zsh"]))
    end

    it "passes autoremove as --autoremove" do
      tool.call(packages: ["zsh"], autoremove: true)
      expect(tool).to have_received(:execute)
        .with(hash_including(arguments: ["install", "--autoremove", "-y", "zsh"]))
    end

    it "passes local_only as -l" do
      tool.call(packages: ["./zsh-5.9.txz"], local_only: true)
      expect(tool).to have_received(:execute)
        .with(hash_including(arguments: ["install", "-l", "-y", "./zsh-5.9.txz"]))
    end

    it "passes the glob match as -g" do
      tool.call(packages: ["zsh*"], match: "glob")
      expect(tool).to have_received(:execute)
        .with(hash_including(arguments: ["install", "-y", "-g", "zsh*"]))
    end

    it "passes the regex match as -x" do
      tool.call(packages: ["^zsh-[0-9]+"], match: "regex")
      expect(tool).to have_received(:execute)
        .with(hash_including(arguments: ["install", "-y", "-x", "^zsh-[0-9]+"]))
    end

    it "passes each repository as -r" do
      tool.call(packages: ["zsh"], repositories: %w[FreeBSD local])
      expect(tool).to have_received(:execute).with(
        hash_including(
          arguments: ["install", "-y", "-r", "FreeBSD", "-r", "local", "zsh"]
        )
      )
    end

    it "passes every argument in a fixed order" do
      arguments = [
        "install", "-A", "-f", "-I", "-l", "-n", "-q", "-U", "--autoremove",
        "-y", "-g", "-r", "FreeBSD", "zsh"
      ]
      tool.call(
        packages: ["zsh"], dry_run: true, no_repo_update: true, quiet: true,
        force: true, no_scripts: true, automatic: true, autoremove: true,
        local_only: true, match: "glob", repositories: ["FreeBSD"]
      )
      expect(tool).to have_received(:execute).with(hash_including(arguments:))
    end

    it "forwards the timeout" do
      tool.call(packages: ["zsh"], timeout: 600)
      expect(tool).to have_received(:execute).with(hash_including(timeout: 600))
    end

    it "passes the max bytes" do
      tool.call(packages: ["zsh"], max_bytes: 100)
      expect(tool).to have_received(:execute).with(hash_including(max_bytes: 100))
    end

    it "returns the result as it is when the install succeeded" do
      expect(tool.call(packages: ["zsh"])).to eq(result)
    end

    it "returns the result as it is when the install failed" do
      stderr = "pkg: No packages available to install matching 'foo' have been found " \
               "in the repositories\n"
      allow(tool).to receive(:execute).and_return({ok: false, stdout: "", stderr:})
      expect(tool.call(packages: ["foo"])).to eq({ok: false, stdout: "", stderr:})
    end
  end

  describe "validation" do
    it "raises when there are no packages" do
      expect { tool.call(packages: []) }
        .to raise_error("packages must be one or more packages")
    end

    it "raises when a package is empty" do
      expect { tool.call(packages: [""]) }
        .to raise_error("a package can't be empty")
    end

    it "raises when a package begins with a dash" do
      expect { tool.call(packages: ["-n"]) }
        .to raise_error("a package can't begin with '-'")
    end

    it "raises when the match is unknown" do
      expect { tool.call(packages: ["zsh"], match: "fuzzy") }
        .to raise_error("match must be one of: exact, case-sensitive, glob, case-insensitive, regex")
    end

    it "raises when a repository is empty" do
      expect { tool.call(packages: ["zsh"], repositories: [""]) }
        .to raise_error("a repository can't be empty")
    end
  end
end
