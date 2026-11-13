require "tmpdir"

RSpec.describe LLM::Tool::Unix::Cat do
  let(:tool) { described_class.new }

  it "runs cat through #exec" do
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, "a.txt"), "a\n")
      File.write(File.join(dir, "b.txt"), "b\n")
      allow(tool).to receive(:exec).and_return({ok: true, stdout: "a\nb\n"})
      tool.call(paths: ["a.txt", "b.txt"], number: true)
      expect(tool).to have_received(:exec).once.with(
        command: "cat",
        arguments: ["-n", "--", "a.txt", "b.txt"],
        timeout: 60
      )
    end
  end

  it "raises when paths is empty" do
    expect { tool.call(paths: []) }.to raise_error(LLM::Error, /'paths' must not be empty/)
  end
end
