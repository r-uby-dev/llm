require "tmpdir"

RSpec.describe LLM::Tool::Find do
  let(:tool) { described_class.new }

  it "runs find through #exec" do
    allow(tool).to receive(:exec).and_return({ok: true, stdout: "a.rb\nb.rb\n"})
    tool.call(path: "lib", name: "*.rb")
    expect(tool).to have_received(:exec).once.with(
      command: "find",
      arguments: ["--", "lib", "-name", "*.rb"],
      timeout: 60
    )
  end

  it "raises when name is empty" do
    expect { tool.call(name: "") }.to raise_error(LLM::Error, /'name' must not be empty/)
  end
end
