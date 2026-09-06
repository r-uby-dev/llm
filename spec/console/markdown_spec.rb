# frozen_string_literal: true

require "setup"
require "llm/console"

RSpec.describe LLM::Console::Markdown do
  describe "typographic symbols" do
    it "renders an ellipsis for '...'" do
      expect(rendered("...")).to eq("…")
    end

    it "renders en and em dashes" do
      expect(rendered("a -- b --- c")).to eq("a – b — c")
    end

    it "renders smart quotes" do
      expect(rendered("'hi' \"hi\"")).to eq("‘hi’ “hi”")
    end

    it "keeps surrounding text intact" do
      expect(rendered("some words ... more")).to eq("some words … more")
    end
  end

  describe "github-style fenced code blocks" do
    let(:ast) { described_class.new("```ruby\nputs 1\n```", 80).ast }

    it "does not render the backtick fence" do
      expect(ast.map { _1[:text] }.join).not_to include("```")
    end

    it "renders the language label" do
      expect(ast.map { _1[:text] }.join).to include("ruby")
    end

    it "renders the code in green" do
      node = ast.find { _1[:text] == "puts 1\n" }
      expect(node[:attrs]).to eq(LLM::Console::Color.green)
    end
  end

  ##
  # Returns the concatenated text of the rendered AST.
  # @param [String] text
  # @return [String]
  def rendered(text)
    described_class.new(text, 80).ast.map { _1[:text] }.join
  end
end
