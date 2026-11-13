require "tmpdir"

RSpec.describe LLM::Tool::Apropos do
  let(:tool) { described_class.new }

  it "runs apropos through #exec" do
    allow(tool).to receive(:exec).and_return({ok: true, stdout: "git (1) - the stupid content tracker\n"})
    expect(tool.call(name: "git")).to eq({ok: true, stdout: "git (1) - the stupid content tracker\n"})
    expect(tool).to have_received(:exec).once.with(
      command: "apropos",
      arguments: ["--", "git"],
      timeout: 30
    )
  end
end
