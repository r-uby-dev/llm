# frozen_string_literal: true

require "setup"
require "llm/console"

RSpec.describe LLM::Console::Markdown do
  subject(:markdown) { described_class.new(text, 80) }
  let(:text) { "hi" }
  let(:nodes) { markdown.ast }

  describe "literal text" do
    it "keeps an ellipsis as typed" do
      expect(rendered("...")).to eq("...")
    end

    it "keeps en and em dashes as typed" do
      expect(rendered("a -- b --- c")).to eq("a -- b --- c")
    end

    it "keeps straight quotes as typed" do
      input = %q('hi' "hi")
      expect(rendered(input)).to eq(input)
    end

    it "keeps surrounding text intact" do
      expect(rendered("some words ... more")).to eq("some words ... more")
    end
  end

  describe "github-style fenced code blocks" do
    let(:text) { "```ruby\nputs 1\n```" }

    it "does not render the backtick fence" do
      expect(nodes.map { it[:text] }.join).not_to include("```")
    end

    it "renders the language label" do
      expect(nodes.map { it[:text] }.join).to include("ruby")
    end

    it "renders the code in green" do
      node = nodes.find { it[:text] == "puts 1\n" }
      expect(node[:attrs]).to eq(LLM::Console::Color.green)
    end
  end

  describe "when given HTML" do
    it "renders an empty HTML tag literally" do
      expect(rendered("<b></b>")).to eq("<b></b>")
    end

    it "renders HTML tags with content literally" do
      expect(rendered("before <b>bold</b> after")).to eq("before <b>bold</b> after")
    end

    it "renders multiple tags literally" do
      expect(rendered("<b>bold</b> <i>it</i>")).to eq("<b>bold</b> <i>it</i>")
    end

    it "preserves tag attributes" do
      input = '<a href="x">link</a>'
      expect(rendered(input)).to eq(input)
    end

    it "preserves boolean and data attributes" do
      input = '<div class="box" data-id="7" hidden>content</div>'
      expect(rendered(input)).to eq(input)
    end

    it "preserves an img with a source and alt" do
      input = '<img src="a.png" alt="an image">'
      expect(rendered(input)).to eq(input)
    end

    it "renders a void element self-closing" do
      expect(rendered("<br>")).to eq("<br>")
      expect(rendered("<hr>")).to eq("<hr>")
    end

    it "renders nested tags literally" do
      input = "<div><p>hi</p><p>bye</p></div>"
      expect(rendered(input)).to eq(input)
    end

    it "renders an HTML comment literally" do
      expect(rendered("<!-- a comment -->")).to eq("<!-- a comment -->")
    end

    it "renders emphasis as styled text" do
      expect(rendered("use <b>*not italic*</b>")).to eq("use <b>not italic</b>")
    end

    it "renders an unclosed tag literally without raising" do
      expect(rendered("compare a < b")).to eq("compare a < b")
    end

    it "handles a trailing less-than without raising" do
      expect(rendered("<b>bold")).to eq("<b>bold")
    end

    it "renders a bare pipe literally" do
      expect(rendered("|foo|")).to eq("|foo|")
    end

    it "renders a pipe in prose literally" do
      expect(rendered("prefix |bar| suffix")).to eq("prefix |bar| suffix")
    end

    it "renders pipe lines without a delimiter literally" do
      expect(rendered("| a | b |\n| 1 | 2 |")).to eq("| a | b |\n| 1 | 2 |")
    end

    it "renders a real pipe table" do
      expect(rendered("| a | b |\n|---|---|\n| 1 | 2 |")).to eq("| a | b |\n| 1 | 2 |")
    end
  end

  def rendered(text)
    described_class.new(text, 80).ast.map { it[:text] }.join
  end
end
