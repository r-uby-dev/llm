# frozen_string_literal: true

require "setup"
require "llm/tools/bsd"

RSpec.describe LLM::Tool::BSD::PkgSearch do
  let(:tool) { described_class.new }
  let(:shell) { instance_double(LLM::Tool::Exec) }
  let(:result) { {ok: true, stdout: "zsh-5.9  The Z shell\n", stderr: ""} }

  before do
    allow(LLM::Tool::Exec).to receive(:new).and_return(shell)
    allow(shell).to receive(:call).and_return(result)
  end

  describe ".function" do
    let(:params) { described_class.function.params }

    it "defines every param a search takes" do
      expect(params.properties.keys).to contain_exactly(
        "pattern", "field", "match", "case_sensitive", "modifiers", "repositories",
        "raw", "raw_format", "quiet", "no_repo_update", "timeout", "max_bytes"
      )
    end

    it "marks the pattern param as required" do
      expect(params.properties[:pattern]).to be_required
    end

    it "defines the flags as booleans" do
      expect(params.properties[:raw]).to be_a(LLM::Schema::Boolean)
      expect(params.properties[:case_sensitive]).to be_a(LLM::Schema::Boolean)
    end

    it "defaults the match to regex and the timeout to 120 seconds" do
      expect(params.properties[:match].default).to eq("regex")
      expect(params.properties[:timeout].default).to eq(120)
    end
  end

  describe "#call" do
    it "searches the names with no flags" do
      tool.call(pattern: "zsh")
      expect(shell).to have_received(:call).with(
        command: "pkg",
        arguments: ["search", "zsh"],
        timeout: 120,
        max_bytes: LLM::Tool::Exec.max_bytes
      )
    end

    it "passes the field as -S" do
      tool.call(pattern: "shell", field: "comment-description")
      expect(shell).to have_received(:call)
        .with(hash_including(arguments: ["search", "-S", "comment-description", "shell"]))
    end

    it "passes the exact match as -e" do
      tool.call(pattern: "zsh", match: "exact")
      expect(shell).to have_received(:call)
        .with(hash_including(arguments: ["search", "-e", "zsh"]))
    end

    it "passes the glob match as -g" do
      tool.call(pattern: "zsh*", match: "glob")
      expect(shell).to have_received(:call)
        .with(hash_including(arguments: ["search", "-g", "zsh*"]))
    end

    it "passes -i when the case does not matter" do
      tool.call(pattern: "Zsh", case_sensitive: false)
      expect(shell).to have_received(:call)
        .with(hash_including(arguments: ["search", "-i", "Zsh"]))
    end

    it "passes each modifier as -Q" do
      tool.call(pattern: "zsh", modifiers: %w[full depends-on])
      expect(shell).to have_received(:call).with(
        hash_including(
          arguments: ["search", "-Q", "full", "-Q", "depends-on", "zsh"]
        )
      )
    end

    it "passes each repository as -r" do
      tool.call(pattern: "zsh", repositories: %w[FreeBSD local])
      expect(shell).to have_received(:call).with(
        hash_including(
          arguments: ["search", "-r", "FreeBSD", "-r", "local", "zsh"]
        )
      )
    end

    it "passes raw as -R and the format as --raw-format" do
      tool.call(pattern: "zsh", raw: true, raw_format: "json-compact")
      expect(shell).to have_received(:call).with(
        hash_including(
          arguments: ["search", "-R", "--raw-format", "json-compact", "zsh"]
        )
      )
    end

    it "leaves the flags out when nothing but a pattern is given" do
      tool.call(pattern: "zsh")
      expect(shell).to have_received(:call)
        .with(hash_including(arguments: ["search", "zsh"]))
    end

    it "passes quiet as -q" do
      tool.call(pattern: "zsh", quiet: true)
      expect(shell).to have_received(:call)
        .with(hash_including(arguments: ["search", "-q", "zsh"]))
    end

    it "passes no_repo_update as -U" do
      tool.call(pattern: "zsh", no_repo_update: true)
      expect(shell).to have_received(:call)
        .with(hash_including(arguments: ["search", "-U", "zsh"]))
    end

    it "passes every argument in a fixed order" do
      arguments = [
        "search", "-q", "-R", "--raw-format", "yaml", "-U", "-S", "comment",
        "-Q", "size", "-i", "-g", "-r", "FreeBSD", "zsh*"
      ]
      tool.call(
        pattern: "zsh*", field: "comment", match: "glob", case_sensitive: false,
        modifiers: ["size"], repositories: ["FreeBSD"], raw: true,
        raw_format: "yaml", quiet: true, no_repo_update: true
      )
      expect(shell).to have_received(:call).with(hash_including(arguments:))
    end

    it "forwards the timeout" do
      tool.call(pattern: "zsh", timeout: 10)
      expect(shell).to have_received(:call).with(hash_including(timeout: 10))
    end

    it "passes the max bytes" do
      tool.call(pattern: "zsh", max_bytes: 100)
      expect(shell).to have_received(:call).with(hash_including(max_bytes: 100))
    end

    it "returns the result as it is when the search matched" do
      expect(tool.call(pattern: "zsh")).to eq(result)
    end

    it "returns the result as it is when the search failed" do
      stderr = "pkg: Repository FreeBSD cannot be opened. 'pkg update' required\n"
      allow(shell).to receive(:call).and_return({ok: false, stdout: "", stderr:})
      expect(tool.call(pattern: "zsh")).to eq({ok: false, stdout: "", stderr:})
    end
  end

  describe "validation" do
    it "raises when the pattern is empty" do
      expect { tool.call(pattern: "") }
        .to raise_error("pattern can't be empty")
    end

    it "raises when the pattern begins with a dash" do
      expect { tool.call(pattern: "-x") }
        .to raise_error("a pattern can't begin with '-'")
    end

    it "raises when the field is unknown" do
      expect { tool.call(pattern: "zsh", field: "depends-on") }
        .to raise_error("field must be one of: pkg-name, name, origin, comment, " \
                        "comment-description, description")
    end

    it "raises when the match is unknown" do
      expect { tool.call(pattern: "zsh", match: "fuzzy") }
        .to raise_error("match must be one of: regex, exact, glob")
    end

    it "raises when the raw format is unknown" do
      expect { tool.call(pattern: "zsh", raw: true, raw_format: "xml") }
        .to raise_error("raw_format must be one of: json, json-compact, ucl, yaml")
    end

    it "raises when the raw format is given without raw" do
      expect { tool.call(pattern: "zsh", raw_format: "json") }
        .to raise_error("raw_format needs raw to print a manifest")
    end

    it "raises when a modifier is empty" do
      expect { tool.call(pattern: "zsh", modifiers: [""]) }
        .to raise_error("a modifier can't be empty")
    end

    it "raises when a repository is empty" do
      expect { tool.call(pattern: "zsh", repositories: [""]) }
        .to raise_error("a repository can't be empty")
    end
  end
end
