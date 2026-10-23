# frozen_string_literal: true

RSpec.shared_examples "LLM: web search" do |dirname, options = {}|
  vcr = lambda do |basename|
    {vcr: {cassette_name: "#{dirname}/web_search/#{basename}"}.merge(options)}
  end

  context "when given a search query", vcr.call("llm_web_search") do
    let(:query) { "Summarize today's news" }
    subject(:response) { llm.web_search(query: query) }

    it "provides a response" do
      expect(response).to be_a(LLM::Response)
    end
  end
end
