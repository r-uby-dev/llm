require "tmpdir"

RSpec.describe LLM::Tool::Nm do
  let(:tool) { described_class.new }

  it "runs nm through #exec" do
    Dir.mktmpdir do |dir|
      path = File.join(dir, "a.o")
      File.write(path, "")
      allow(tool).to receive(:exec).and_return({ok: true, stdout: "0000000000000000 T main\n"})
      tool.call(path: "a.o", directory: dir)
      expect(tool).to have_received(:exec).once.with(
        command: "nm",
        arguments: ["--", "a.o"],
        chdir: dir,
        timeout: 60
      )
    end
  end
end
