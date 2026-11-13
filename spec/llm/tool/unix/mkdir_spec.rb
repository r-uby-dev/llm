require "tmpdir"

RSpec.describe LLM::Tool::Unix::Mkdir do
  let(:tool) { described_class.new }

  it "runs mkdir through #exec" do
    Dir.mktmpdir do |dir|
      allow(tool).to receive(:exec).and_return({ok: true, stdout: "", stderr: ""})
      tool.call(path: File.join(dir, "a", "b"), parents: true)
      expect(tool).to have_received(:exec).once.with(
        command: "mkdir",
        arguments: ["-p", "--", File.join(dir, "a", "b")],
        timeout: 60
      )
    end
  end

  it "raises when path is empty" do
    expect { tool.call(path: "") }.to raise_error(LLM::Error, /'path' must not be empty/)
  end
end
