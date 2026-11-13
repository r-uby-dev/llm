require "tmpdir"

RSpec.describe LLM::Tool::PkgSearch do
  let(:tool) { described_class.new }

  it "runs pkg search through #exec" do
    allow(tool).to receive(:exec).and_return({ok: true, stdout: "git-2.45.0\n"})
    tool.call(name: "^git$")
    expect(tool).to have_received(:exec).once.with(
      command: "pkg",
      arguments: ["search", "--", "^git$"],
      timeout: 60
    )
  end
end
