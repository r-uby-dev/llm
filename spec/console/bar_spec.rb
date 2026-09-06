# frozen_string_literal: true

require "setup"
require "llm/console"

RSpec.describe LLM::Console::Bar do
  describe "#to_s" do
    context "when given a fraction" do
      subject(:bar) { described_class.new(fraction: Rational(500, 1000)) }

      it "shows the remaining percentage" do
        expect(bar.to_s).to eq("│█████     │ 50.0%")
      end
    end

    context "when the fraction is unknown" do
      subject(:bar) { described_class.new(fraction: nil) }

      it "renders an unknown bar" do
        expect(bar.to_s).to eq("│██████████│ ???")
      end
    end
  end
end
