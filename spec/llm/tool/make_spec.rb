require "tmpdir"

RSpec.describe LLM::Tool::Make do
  let(:tool) { described_class.new }

  it "runs make through #exec" do
    Dir.mktmpdir do |dir|
      allow(tool).to receive(:exec).and_return({ok: true, stdout: "all\n"})
      tool.call(directory: dir, target: "all")
      expect(tool).to have_received(:exec).once.with(
        command: "make",
        arguments: ["--", "all"],
        chdir: dir,
        timeout: 120
      )
    end
  end

  it "raises when directory does not exist" do
    expect { tool.call(directory: "/no/such/dir") }.to raise_error(LLM::Error, /'directory' must be one that exists/)
  end
end
