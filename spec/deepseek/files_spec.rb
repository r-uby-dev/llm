# frozen_string_literal: true

require "setup"

RSpec.describe "LLM::DeepSeek::Files" do
  let(:key) { ENV["DEEPSEEK_SECRET"] || "TOKEN" }
  let(:provider) { LLM.deepseek(key:) }

  context "when given a successful create operation (haiku1.txt)",
          vcr: {cassette_name: "deepseek/files/successful_create_haiku1"} do
    subject(:file) { provider.files.create(file: "spec/fixtures/documents/haiku1.txt") }

    it "is successful" do
      expect(file).to be_instance_of(LLM::Response)
    ensure
      provider.files.delete(file:)
    end

    it "returns a file object" do
      expect(file).to have_attributes(
        id: instance_of(String),
        filename: "haiku1.txt",
        purpose: "user_data"
      )
    ensure
      provider.files.delete(file:)
    end
  end

  context "when given a successful get operation (haiku1.txt)",
          vcr: {cassette_name: "deepseek/files/successful_get_haiku1"} do
    let(:file) { provider.files.create(file: "spec/fixtures/documents/haiku1.txt") }
    subject { provider.files.get(file:) }

    it "is successful" do
      is_expected.to be_instance_of(LLM::Response)
    ensure
      provider.files.delete(file:)
    end

    it "returns a file object" do
      is_expected.to have_attributes(
        id: file.id,
        filename: "haiku1.txt",
        purpose: "user_data"
      )
    ensure
      provider.files.delete(file:)
    end
  end

  context "when given a successful all operation",
          vcr: {cassette_name: "deepseek/files/successful_all"} do
    let!(:files) do
      [
        provider.files.create(file: "spec/fixtures/documents/haiku1.txt"),
        provider.files.create(file: "spec/fixtures/documents/haiku2.txt")
      ]
    end
    subject(:filelist) { provider.files.all }

    it "is successful" do
      expect(filelist).to be_instance_of(LLM::Response)
    ensure
      files.each { |file| provider.files.delete(file:) }
    end

    it "returns an array of file objects" do
      expect(filelist[0..1]).to match_array(
        [
          have_attributes(
            filename: "haiku1.txt",
            purpose: "user_data"
          ),
          have_attributes(
            filename: "haiku2.txt",
            purpose: "user_data"
          )
        ]
      )
    ensure
      files.each { |file| provider.files.delete(file:) }
    end
  end

  context "when given a successful delete operation (haiku1.txt)",
          vcr: {cassette_name: "deepseek/files/successful_delete_haiku1"} do
    let(:file) { provider.files.create(file: "spec/fixtures/documents/haiku1.txt") }
    subject { provider.files.delete(file:) }

    it "is successful" do
      is_expected.to be_instance_of(LLM::Response)
    end

    it "returns deleted status" do
      is_expected.to have_attributes(
        deleted: true
      )
    end
  end
end
