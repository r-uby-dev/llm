# frozen_string_literal: true

require "setup"
require "tmpdir"
require "llm/tools/git"

RSpec.describe LLM::Tool::Git::Log do
  let(:tool) { described_class.new }
  let(:dir) { Dir.mktmpdir("git-log-spec") }

  before do
    skip "git is not on the PATH" unless command_available?("git")
    Dir.chdir(dir) { make_repo! }
  end

  around do |example|
    Dir.chdir(dir) { example.call }
    FileUtils.rm_rf(dir)
  end

  describe ".function" do
    let(:params) { described_class.function.params }

    it "defines the rev, path and max_count parameters" do
      expect(params.properties.keys).to contain_exactly(:rev, :path, :max_count)
    end

    it "defaults rev to HEAD" do
      expect(params.properties[:rev].default).to eq("HEAD")
    end

    it "defaults max_count to 10" do
      expect(params.properties[:max_count].default).to eq(10)
    end
  end

  describe "#call" do
    it "lists the commits, newest first" do
      res = tool.call
      expect(res[:ok]).to be(true)
      expect(res[:stdout]).to match(/\A[0-9a-f]{7,40} initial\n\z/)
    end

    it "limits the number of commits it returns" do
      commit!("second")
      expect(tool.call(max_count: 1)[:stdout].lines.size).to eq(1)
    end

    it "filters commits by path" do
      commit!("other", "other.txt")
      res = tool.call(path: "other.txt")
      expect(res[:stdout]).to include("other")
      expect(res[:stdout]).to_not include("initial")
    end
  end
end
