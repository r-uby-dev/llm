require "tmpdir"

RSpec.describe LLM::Tool::Rg do
  let(:tool) { described_class.new }

  before do
    allow(tool).to receive(:ripgrep?).and_return(ripgrep)
    allow(tool).to receive(:exec).and_return({ok: true, stdout: "lib/a.rb:1:hello\n"})
  end

  Dir.mktmpdir do |dir|
    context "when ripgrep is installed" do
      let(:ripgrep) { true }

      it "runs rg through #exec" do
        Dir.chdir(dir) { tool.call(pattern: "hello", glob: "*.rb", ignore_case: true) }
        expect(tool).to have_received(:exec).once.with(
          command: "rg",
          arguments: ["--line-number", "--no-heading", "--color=never", "--ignore-case", "--glob", "*.rb", "--", "hello", "."],
          timeout: 60
        )
      end
    end

    context "when ripgrep is not installed" do
      let(:ripgrep) { false }

      it "falls back to grep -R" do
        tool.call(pattern: "hello", path: "lib")
        expect(tool).to have_received(:exec).once.with(
          command: "grep",
          arguments: ["-R", "-n", "-H", "--", "hello", "lib"],
          timeout: 60
        )
      end
    end
  end
end
