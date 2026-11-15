# frozen_string_literal: true

require "setup"
require "llm/tools/ruby-lang"

RSpec.describe LLM::Tool::RubyLang::Issues do
  let(:tool) { described_class.new }
  let(:result) { {ok: true, status: 200, body: {"issues" => [], "total_count" => 0}} }

  before do
    allow(tool).to receive(:get).and_return(result)
  end

  describe ".function" do
    let(:params) { described_class.function.params }

    it "defines every param a listing takes" do
      expect(params.properties.keys).to contain_exactly(
        "status", "subject", "project_id", "tracker_id", "author_id",
        "assigned_to_id", "include", "sort", "limit", "offset", "timeout"
      )
    end

    it "defaults to the open issues, newest first, 25 of them" do
      expect(params.properties[:status].default).to eq("open")
      expect(params.properties[:sort].default).to eq("updated_on:desc")
      expect(params.properties[:limit].default).to eq(25)
    end

    it "constrains the status to the three groups" do
      expect(params.properties[:status].enum).to eq(%w[open closed *])
    end
  end

  describe "#call" do
    it "lists the open issues with the default filters" do
      tool.call
      expect(tool).to have_received(:get).with(
        "/issues.json",
        {status_id: "open", subject: nil, project_id: nil, tracker_id: nil,
         author_id: nil, assigned_to_id: nil, include: [], sort: "updated_on:desc",
         limit: 25, offset: 0},
        timeout: 30
      )
    end

    it "matches the subject as a substring" do
      tool.call(subject: "Ractor")
      expect(tool).to have_received(:get)
        .with(anything, hash_including(subject: "~Ractor"), timeout: 30)
    end

    it "passes the status, the tracker and the assignee" do
      tool.call(status: "*", tracker_id: 1, assigned_to_id: 2)
      expect(tool).to have_received(:get).with(
        anything,
        hash_including(status_id: "*", tracker_id: 1, assigned_to_id: 2),
        timeout: 30
      )
    end

    it "passes the page" do
      tool.call(limit: 100, offset: 200)
      expect(tool).to have_received(:get)
        .with(anything, hash_including(limit: 100, offset: 200), timeout: 30)
    end

    it "passes the journals as include" do
      tool.call(include: ["journals"])
      expect(tool).to have_received(:get)
        .with(anything, hash_including(include: ["journals"]), timeout: 30)
    end

    it "returns the result as it is" do
      expect(tool.call).to eq(result)
    end
  end

  describe "validation" do
    it "raises when the status is not one of the three" do
      expect { tool.call(status: "pending") }
        .to raise_error("status must be one of: open, closed, *")
    end

    it "raises when the subject is empty" do
      expect { tool.call(subject: "") }
        .to raise_error("a subject can't be empty")
    end

    it "raises when an id is not positive" do
      expect { tool.call(tracker_id: 0) }
        .to raise_error("an id must be a positive integer")
    end

    it "raises when the sort is not a field and a direction" do
      expect { tool.call(sort: "updated_on DESC; drop") }
        .to raise_error("sort must be a field and a direction, eg updated_on:desc")
    end

    it "raises when the limit is above what Redmine serves" do
      expect { tool.call(limit: 1000) }
        .to raise_error("limit must be between 1 and 100")
    end

    it "raises when the offset is negative" do
      expect { tool.call(offset: -1) }
        .to raise_error("offset must be zero or more")
    end
  end
end
