# frozen_string_literal: true

require "setup"

##
# A leaf's enum is a list of values of that leaf's type.
# A list passed as one argument becomes a list of one list,
# and a schema like that is one a provider refuses - for the
# whole request, naming only the tool that carried it.
RSpec.describe LLM::Schema::Enum do
  describe "values given one at a time" do
    let(:leaf) { described_class["apple", "orange"] }

    it "keeps them as the enum" do
      expect(leaf.to_h[:enum]).to eq(%w[apple orange])
    end
  end

  describe "a list given as one argument" do
    it "is refused rather than turned into a schema" do
      expect { described_class[%w[apple orange]] }
        .to raise_error(LLM::Error, /Enum\[\*values\]/)
    end
  end
end
