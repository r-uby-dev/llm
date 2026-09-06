# frozen_string_literal: true

require "setup"
require "llm/console"

RSpec.describe LLM::Console::Walker do
  let(:items) { %w[one two three] }
  let(:walker) { described_class.new(items) }

  describe "#prev" do
    it "walks backward from the last item" do
      expect(walker.prev).to eq("three")
      expect(walker.prev).to eq("two")
      expect(walker.prev).to eq("one")
    end

    it "clamps at the first item" do
      3.times { walker.prev }
      expect(walker.prev).to eq("one")
    end
  end

  describe "#next" do
    it "walks forward through the items" do
      3.times { walker.prev }
      expect(walker.next).to eq("two")
      expect(walker.next).to eq("three")
    end

    it "returns an empty string at the end of the items" do
      walker.prev
      expect(walker.next).to eq("")
    end

    it "stays empty once at the end" do
      walker.prev
      walker.next
      expect(walker.next).to eq("")
    end

    it "allows prev to return from the empty slot" do
      walker.prev
      walker.next
      expect(walker.prev).to eq("three")
    end
  end

  context "when empty" do
    let(:items) { [] }

    it "returns nil for prev and next" do
      expect(walker.prev).to be_nil
      expect(walker.next).to be_nil
    end
  end
end
