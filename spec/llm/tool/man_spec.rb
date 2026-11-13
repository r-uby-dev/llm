require "tmpdir"

RSpec.describe LLM::Tool::Man do
  let(:tool) { described_class.new }

  it "runs man through #exec" do
    allow(tool).to receive(:exec).and_return({ok: true, stdout: "GIT(1)\n"})
    tool.call(name: "git")
    expect(tool).to have_received(:exec).once.with(
      command: "man",
      arguments: ["-P", "cat", "--", "git"],
      timeout: 30
    )
  end
end
