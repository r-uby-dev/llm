require "tmpdir"

RSpec.describe LLM::Tool::PkgInstall do
  let(:tool) { described_class.new }

  it "runs pkg install through #exec" do
    allow(tool).to receive(:exec).and_return({ok: true, stdout: "", stderr: ""})
    tool.call(names: ["git"], assume_yes: true)
    expect(tool).to have_received(:exec).once.with(
      command: "pkg",
      arguments: ["install", "--yes", "--", "git"],
      timeout: 300
    )
  end

  it "raises when names is empty" do
    expect { tool.call(names: []) }.to raise_error(LLM::Error, /'names' must not be empty/)
  end
end
