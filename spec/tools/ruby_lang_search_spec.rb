# frozen_string_literal: true

require "setup"
require "llm/tools/ruby-lang"

RSpec.describe LLM::Tool::RubyLang::Search do
  let(:tool) { described_class.new }
  let(:result) { {ok: true, status: 200, body: {"results" => []}} }

  before do
    allow(tool).to receive(:get).and_return(result)
  end

  describe ".function" do
    let(:params) { described_class.function.params }

    it "marks the query as required" do
      expect(params.properties[:query]).to be_required
    end

    it "defaults to the issues and to 25 hits" do
      expect(params.properties[:scope].default).to eq("issues")
      expect(params.properties[:limit].default).to eq(25)
      expect(params.properties[:titles_only].default).to be(false)
    end
  end

  describe "#call" do
    it "searches the issues with the words given" do
      tool.call(query: "Ractor")
      expect(tool).to have_received(:get).with(
        "/search.json",
        {q: "Ractor", scope: "issues", titles_only: false, limit: 25, offset: 0},
        timeout: 30
      )
    end

    it "passes the scope and the titles_only flag" do
      tool.call(query: "GC", scope: "wiki", titles_only: true)
      expect(tool).to have_received(:get)
        .with(anything, hash_including(scope: "wiki", titles_only: true), anything)
    end

    it "returns the result as it is" do
      expect(tool.call(query: "Ractor")).to eq(result)
    end
  end

  describe "validation" do
    it "raises when the query is empty" do
      expect { tool.call(query: "  ") }
        .to raise_error("query can't be empty")
    end

    it "raises when the scope is not one Redmine knows" do
      expect { tool.call(query: "GC", scope: "mail") }
        .to raise_error("scope must be one of: all, issues, news, documents, " \
                        "changesets, wiki, messages")
    end
  end
end
