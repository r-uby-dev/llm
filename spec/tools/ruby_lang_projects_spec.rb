# frozen_string_literal: true

require "setup"
require "llm/tools/ruby-lang"

RSpec.describe LLM::Tool::RubyLang::Projects do
  let(:tool) { described_class.new }
  let(:result) { {ok: true, status: 200, body: {"projects" => [], "total_count" => 0}} }

  before do
    allow(tool).to receive(:get).and_return(result)
  end

  describe "#call" do
    it "lists the projects with the trackers beside them" do
      tool.call(include: ["trackers"])
      expect(tool).to have_received(:get).with(
        "/projects.json", {include: ["trackers"], limit: 100, offset: 0}, timeout: 30
      )
    end

    it "passes the page" do
      tool.call(limit: 10, offset: 20)
      expect(tool).to have_received(:get)
        .with(anything, hash_including(limit: 10, offset: 20), timeout: 30)
    end

    it "returns the result as it is" do
      expect(tool.call).to eq(result)
    end
  end

  describe "validation" do
    it "raises when include is not a part of a project" do
      expect { tool.call(include: ["versions"]) }
        .to raise_error("include must be one of: trackers, issue_categories, " \
                        "enabled_modules, time_entry_activities, issue_custom_fields")
    end

    it "raises when the limit is above what Redmine serves" do
      expect { tool.call(limit: 101) }
        .to raise_error("limit must be between 1 and 100")
    end
  end
end
