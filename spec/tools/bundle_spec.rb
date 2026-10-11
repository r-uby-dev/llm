# frozen_string_literal: true

require "setup"
require "tmpdir"
require "llm/tools/bundle"
require "llm/tools/exec"

RSpec.describe LLM::Tool::Bundle do
  let(:tool) { described_class.new }
  ##
  # macOS keeps TMPDIR under /var, a symlink
  # to /private/var, and a command reports the
  # resolved path as its cwd.
  let(:dir) { File.realpath(Dir.mktmpdir("bundle-spec")) }
  let(:gemfile) { File.join(dir, "Gemfile") }

  around do |example|
    original = ENV["BUNDLE_GEMFILE"]
    ENV["BUNDLE_GEMFILE"] = gemfile
    Dir.chdir(dir) { example.run }
  ensure
    ENV["BUNDLE_GEMFILE"] = original
  end

  before do
    File.write(gemfile, "source 'https://rubygems.org'\n")
  end

  describe ".function" do
    let(:params) { described_class.function.params }

    it "has a timeout parameter with a default" do
      expect(params.properties[:timeout].default).to eq(60)
    end

    it "defaults max_bytes to Exec.max_bytes" do
      expect(params.properties[:max_bytes].default).to eq(LLM::Tool::Exec.max_bytes)
    end
  end

  describe "when spawning a real command" do
    before do
      skip "bundle is not on the PATH" unless command_available?("bundle")
      skip "ruby is not on the PATH" unless command_available?("ruby")
    end

    it "runs the command through bundle exec" do
      expect(tool.call(arguments: ["exec", "ruby", "-e", "puts 123"], timeout: 60))
        .to include(ok: true, stdout: "123\n", stderr: "")
    end

    context "when BUNDLE_GEMFILE is set" do
      it "passes the set value to the command" do
        res = tool.call(
          arguments: ["exec", "ruby", "-e", "puts ENV[\"BUNDLE_GEMFILE\"]"],
          timeout: 60
        )
        expect(res[:stdout]).to eq("#{gemfile}\n")
      end
    end

    context "when BUNDLE_GEMFILE is not set" do
      around do |example|
        original = ENV["BUNDLE_GEMFILE"]
        ENV.delete("BUNDLE_GEMFILE")
        example.run
      ensure
        ENV["BUNDLE_GEMFILE"] = original
      end

      it "defaults to a Gemfile in the cwd and passes it to the command" do
        res = tool.call(
          arguments: ["exec", "ruby", "-e", "puts ENV[\"BUNDLE_GEMFILE\"]"],
          timeout: 60
        )
        expect(res[:stdout]).to eq("#{File.join(dir, "Gemfile")}\n")
      end
    end
  end

  ##
  # True when the given executable is present on the PATH.
  def command_available?(name)
    (ENV["PATH"] || "").split(File::PATH_SEPARATOR).any? do |dir|
      File.executable?(File.join(dir, name))
    end
  end
end
