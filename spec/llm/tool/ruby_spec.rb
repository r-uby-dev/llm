require "tmpdir"

RSpec.describe LLM::Tool::Ruby do
  let(:tool) { described_class.new }

  it "runs ruby through #exec" do
    allow(tool).to receive(:exec).and_return({ok: true, stdout: "1\n"})
    tool.call(code: "puts 1")
    expect(tool).to have_received(:exec).once.with(
      command: "ruby",
      arguments: ["-e", "puts 1"],
      timeout: 60
    )
  end

  it "raises when code is empty" do
    expect { tool.call(code: "") }.to raise_error(LLM::Error, /'code' must not be empty/)
  end
end
