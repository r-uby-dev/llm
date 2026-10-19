# frozen_string_literal: true

require "setup"

RSpec.describe "LLM.json=" do
  around do |example|
    adapter = LLM.json
    example.run
  ensure
    LLM.json = adapter
  end

  it "rejects the removed Yajl adapter" do
    expect { LLM.json = :yajl }.to raise_error(TypeError, "Adapter must be a subclass of LLM::JSONAdapter")
  end

  it "does not define the removed Yajl adapter" do
    expect(LLM::JSONAdapter.const_defined?(:Yajl, false)).to be(false)
  end
end

RSpec.describe LLM::JSONAdapter::JSON do
  describe "when dumping an invalid UTF-8 string" do
    let(:invalid_utf8) { "\xFF\xFE".b.force_encoding("UTF-8") }

    it "does not raise a generator error" do
      expect { described_class.dump({"a" => invalid_utf8}) }.not_to raise_error
    end

    it "replaces the invalid bytes with the replacement character" do
      expect(described_class.dump({"a" => invalid_utf8})).to include("\uFFFD")
    end
  end

  describe "when dumping a string tagged as binary" do
    let(:binary) { "\xC3\xA9".b }

    it "reinterprets the bytes as UTF-8" do
      expect(described_class.dump({"a" => binary})).to include("é")
    end
  end

  describe "when dumping a string in another encoding" do
    let(:latin1) { "café".encode("ISO-8859-1") }

    it "transcodes the string to UTF-8" do
      expect(described_class.dump({"a" => latin1})).to include("café")
    end
  end
end
