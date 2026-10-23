# frozen_string_literal: true

require "setup"

RSpec.describe "LLM::Anthropic::Files" do
  let(:key) { ENV["ANTHROPIC_SECRET"] || "TOKEN" }
  let(:provider) { LLM.anthropic(key:) }

  context "when given a successful create operation (haiku1.txt)",
          vcr: {cassette_name: "anthropic/files/successful_create_haiku1"} do
    subject(:file) { provider.files.create(file: "spec/fixtures/documents/haiku1.txt") }

    it "is successful" do
      expect(file).to be_instance_of(LLM::Response)
    ensure
      provider.files.delete(file:)
    end

    it "returns a file object" do
      expect(file).to have_attributes(
        id: instance_of(String),
        filename: "haiku1.txt"
      )
    ensure
      provider.files.delete(file:)
    end
  end

  context "when given a successful create operation (haiku2.txt)",
          vcr: {cassette_name: "anthropic/files/successful_create_haiku2"} do
    subject(:file) { provider.files.create(file: "spec/fixtures/documents/haiku2.txt") }

    it "is successful" do
      expect(file).to be_instance_of(LLM::Response)
    ensure
      provider.files.delete(file:)
    end

    it "returns a file object" do
      expect(file).to have_attributes(
        id: instance_of(String),
        filename: "haiku2.txt"
      )
    ensure
      provider.files.delete(file:)
    end
  end

  context "when given a successful create operation (readme.md)",
          vcr: {cassette_name: "anthropic/files/successful_create_readme"} do
    subject(:file) { provider.files.create(file: "spec/fixtures/documents/readme.md") }

    it "is successful" do
      expect(file).to be_instance_of(LLM::Response)
    ensure
      provider.files.delete(file:)
    end

    it "returns a file object" do
      expect(file).to have_attributes(
        id: instance_of(String),
        filename: "readme.md"
      )
    ensure
      provider.files.delete(file:)
    end
  end

  context "when given a successful delete operation (haiku3.txt)",
          vcr: {cassette_name: "anthropic/files/successful_delete_haiku3"} do
    let(:file) { provider.files.create(file: "spec/fixtures/documents/haiku3.txt") }
    subject { provider.files.delete(file:) }

    it "is successful" do
      is_expected.to be_instance_of(LLM::Response)
    end

    it "returns deleted status" do
      is_expected.to have_attributes(
        type: "file_deleted"
      )
    end
  end

  context "when given a successful get operation (haiku4.txt)",
          vcr: {cassette_name: "anthropic/files/successful_get_haiku4"} do
    let(:file) { provider.files.create(file: "spec/fixtures/documents/haiku4.txt") }
    subject { provider.files.get(file:) }

    it "is successful" do
      is_expected.to be_instance_of(LLM::Response)
    ensure
      provider.files.delete(file:)
    end

    it "returns a file object" do
      is_expected.to have_attributes(
        id: instance_of(String),
        filename: "haiku4.txt"
      )
    ensure
      provider.files.delete(file:)
    end
  end

  context "when given a successful 'retrieve metadata' operation (haiku4.txt)",
        vcr: {cassette_name: "anthropic/files/successful_retrieve_metadata_haiku4"} do
    let(:file) { provider.files.create(file: "spec/fixtures/documents/haiku4.txt") }
    subject { provider.files.retrieve_metadata(file:) }

    it "is successful" do
      is_expected.to be_instance_of(LLM::Response)
    ensure
      provider.files.delete(file:)
    end

    it "returns metadata" do
      is_expected.to have_attributes(
        id: instance_of(String),
        filename: "haiku4.txt",
        mime_type: "text/plain"
      )
    ensure
      provider.files.delete(file:)
    end
  end

  context "when given a successful all operation",
          vcr: {cassette_name: "anthropic/files/successful_all"} do
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
            id: instance_of(String),
            filename: "haiku1.txt"
          ),
          have_attributes(
            id: instance_of(String),
            filename: "haiku2.txt"
          )
        ]
      )
    ensure
      files.each { |file| provider.files.delete(file:) }
    end
  end

  context "when asked to describe the contents of a file",
          vcr: {cassette_name: "anthropic/files/describe_freebsd.sysctl_3.pdf"} do
    subject { ctx.messages.find(&:assistant?).content.downcase[0..2] }

    let(:ctx) { LLM::Context.new(provider) }
    let(:file) { provider.files.create(file: "spec/fixtures/documents/freebsd.sysctl.pdf") }
    let(:prompt) do
      ctx.build_prompt do
        it.user(file)
        it.user("Is this PDF document about FreeBSD?")
        it.user("Answer with yes or no. Nothing else.")
      end
    end

    before { ctx.talk(prompt) }

    it "describes the document" do
      is_expected.to eq("yes")
    ensure
      provider.files.delete(file:)
    end
  end

  context "when asked to describe the contents of a file",
          vcr: {cassette_name: "anthropic/files/describe_freebsd.sysctl_4.pdf"} do
    subject { ctx.messages.find(&:assistant?).content.downcase[0..2] }
    let(:ctx) { LLM::Context.new(provider) }
    let(:file) { provider.files.create(file: "spec/fixtures/documents/freebsd.sysctl.pdf") }

    before do
      ctx.talk([
        "Is this PDF document about FreeBSD?",
        "Answer with yes or no. Nothing else.",
        file
      ])
    end

    it "describes the document" do
      is_expected.to eq("yes")
    ensure
      provider.files.delete(file:)
    end
  end
end
