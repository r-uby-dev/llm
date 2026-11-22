# frozen_string_literal: true

require "setup"
require "llm/tools/exec"
require "rbconfig"

##
# A tool is bounded by its timeout and by nothing else.
# The command it started has to be reported when the
# timeout expires, not waited for: a command that ignores
# the polite signal is one whose `waitpid` may never
# return.
RSpec.describe LLM::Tool::Exec do
  let(:tool) { described_class.new }
  let(:script) { "Signal.trap('TERM') {}; sleep 30" }

  def call
    tool.call(command: RbConfig.ruby, arguments: ["-e", script], timeout: 0.2)
  end

  it "is killed rather than waited for" do
    now = Time.now
    call
    expect((Time.now - now) < 5).to be(true)
  end

  it "says the command was killed" do
    expect(call[:note]).to include("The command was killed after")
  end

  it "answers with what the command had written" do
    expect(call[:stdout]).to be_a(String)
  end
end
