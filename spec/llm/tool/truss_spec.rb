require "tmpdir"

RSpec.describe LLM::Tool::Truss do
  let(:tool) { described_class.new }

  it "runs truss through #exec" do
    Dir.mktmpdir do |dir|
      allow(tool).to receive(:exec).and_return({ok: true, stderr: "execve(2)\n"})
      tool.call(command: "ls", directory: dir)
      expect(tool).to have_received(:exec).once.with(
        command: "truss",
        arguments: ["-f", "ls"],
        chdir: dir,
        timeout: 60
      )
    end
  end

  it "raises when command is empty" do
    expect { tool.call(command: "") }.to raise_error(LLM::Error, /'command' must not be empty/)
  end
end
