require "tmpdir"

RSpec.describe LLM::Tool::Git do
  let(:tool) { described_class.new }
  let(:dir) { Dir.mktmpdir }

  after { FileUtils.remove_entry(dir) }

  it "runs git through #exec" do
    allow(tool).to receive(:exec).and_return({ok: true, stdout: ""})
    tool.call(arguments: ["log", "--oneline"], directory: dir)
    expect(tool).to have_received(:exec).once.with(
      command: "git",
      arguments: ["log", "--oneline"],
      chdir: dir,
      timeout: 60
    )
  end

  it "raises when directory does not exist" do
    expect { tool.call(arguments: ["status"], directory: "/no/such/dir") }.to raise_error(LLM::Error, /'directory' must be one that exists/)
  end
end
