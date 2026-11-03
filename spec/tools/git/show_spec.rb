# frozen_string_literal: true

require "setup"
require "tmpdir"
require "llm/tools/git"

RSpec.describe LLM::Tool::Git::Show do
  let(:tool) { described_class.new }
  let(:dir) { Dir.mktmpdir("git-show-spec") }

  before do
    skip "git is not on the PATH" unless command_available?("git")
    Dir.chdir(dir) { make_repo! }
  end

  around do |example|
    Dir.chdir(dir) { example.call }
    FileUtils.rm_rf(dir)
  end

  describe ".function" do
    it "defaults rev to HEAD" do
      expect(described_class.function.params.properties[:rev].default).to eq("HEAD")
    end

    it "defaults stat to false" do
      expect(described_class.function.params.properties[:stat].default).to be(false)
    end
  end

  describe "#call" do
    it "shows the commit" do
      res = tool.call
      expect(res[:stdout]).to include("initial")
      expect(res[:stdout]).to include("+hello")
    end

    it "shows a diffstat when stat: is true" do
      res = tool.call(stat: true)
      expect(res[:stdout]).to include("file.txt")
      expect(res[:stdout]).to_not include("+hello")
    end

    it "restricts the output to a path" do
      commit!("other", "other.txt")
      expect(tool.call(path: "other.txt")[:stdout]).to include("other.txt")
      expect(tool.call(path: "file.txt")[:stdout]).to_not include("other.txt")
    end
  end
end
