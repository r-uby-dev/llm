# frozen_string_literal: true

require "setup"
require "llm/tools/ruby-lang"

RSpec.describe LLM::Tool::RubyLang::Issue do
  let(:tool) { described_class.new }
  let(:result) { {ok: true, status: 200, body: {"issue" => {"id" => 1}}} }

  before do
    allow(tool).to receive(:get).and_return(result)
  end

  describe ".function" do
    let(:params) { described_class.function.params }

    it "defines every param a read takes" do
      expect(params.properties.keys).to contain_exactly("id", "include", "timeout")
    end

    it "marks the id as required" do
      expect(params.properties[:id]).to be_required
    end

    it "defaults the timeout to 30 seconds" do
      expect(params.properties[:timeout].default).to eq(30)
    end
  end

  describe "#call" do
    it "reads the issue with nothing beside it" do
      tool.call(id: 1)
      expect(tool).to have_received(:get)
        .with("/issues/1.json", {include: []}, timeout: 30)
    end

    it "passes the journals as include" do
      tool.call(id: 42, include: ["journals", "attachments"])
      expect(tool).to have_received(:get)
        .with("/issues/42.json", {include: ["journals", "attachments"]}, timeout: 30)
    end

    it "forwards the timeout" do
      tool.call(id: 1, timeout: 5)
      expect(tool).to have_received(:get).with(anything, anything, timeout: 5)
    end

    it "returns the result as it is" do
      expect(tool.call(id: 1)).to eq(result)
    end
  end

  describe "validation" do
    it "raises when the id is not a positive integer" do
      expect { tool.call(id: 0) }
        .to raise_error("an id must be a positive integer")
    end

    it "raises when include is not a part of an issue" do
      expect { tool.call(id: 1, include: ["comments"]) }
        .to raise_error("include must be one of: journals, attachments, relations, " \
                        "children, changesets, allowed_statuses, watchers")
    end
  end
end
