require "tmpdir"

RSpec.describe LLM::Tool::Cc do
  let(:tool) { described_class.new }

  it "runs cc through #exec" do
    Dir.mktmpdir do |dir|
      path = File.join(dir, "a.c")
      File.write(path, "int main(void) { return 0; }\n")
      allow(tool).to receive(:exec).and_return({ok: true, stdout: "", stderr: ""})
      tool.call(path: "a.c", output: "a.out", directory: dir)
      expect(tool).to have_received(:exec).once.with(
        command: "cc",
        arguments: ["-o", "a.out", "--", "a.c"],
        chdir: dir,
        timeout: 120
      )
    end
  end
end
