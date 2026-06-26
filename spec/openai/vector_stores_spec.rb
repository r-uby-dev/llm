# frozen_string_literal: true

require "setup"

RSpec.describe "LLM::OpenAI::VectorStores" do
  let(:key) { ENV["OPENAI_SECRET"] || "TOKEN" }
  let(:provider) { LLM.openai(key:) }

  context "when given a successful create operation",
          vcr: {cassette_name: "openai/vector_stores/successful_create"} do
    subject(:store) { provider.vector_stores.create_and_poll(name: "test store", file_ids: [file.id], interval:) }
    let(:file) { provider.files.create(file: "spec/fixtures/documents/readme.md") }

    after do
      provider.vector_stores.delete(vector: store)
      provider.files.delete(file:)
    end

    it "is successful" do
      is_expected.to be_ok
    end

    it "includes created status" do
      is_expected.to have_attributes(
        "id" => instance_of(String),
        "object" => "vector_store"
      )
    end
  end

  context "when given a successful get operation",
          vcr: {cassette_name: "openai/vector_stores/successful_get"} do
    let(:store) { provider.vector_stores.create_and_poll(name: "test store", file_ids: [file.id], interval:) }
    let(:file) { provider.files.create(file: "spec/fixtures/documents/haiku1.txt") }
    subject { provider.vector_stores.get(vector: store) }
    after do
      provider.vector_stores.delete(vector: store)
      provider.files.delete(file:)
    end

    it "is successful" do
      is_expected.to be_ok
    end

    it "includes the store" do
      is_expected.to have_attributes(
        "id" => store.id,
        "name" => store.name
      )
    end
  end

  context "when given a successful delete operation",
          vcr: {cassette_name: "openai/vector_stores/successful_delete"} do
    let(:store) { provider.vector_stores.create_and_poll(name: "test store", file_ids: [file.id], interval:) }
    let(:file) { provider.files.create(file: "spec/fixtures/documents/haiku1.txt") }
    subject { provider.vector_stores.delete(vector: store) }
    after { provider.files.delete(file:) }

    it "is successful" do
      is_expected.to be_ok
    end

    it "includes deleted status" do
      is_expected.to have_attributes(
        "deleted" => true
      )
    end
  end

  context "when givee a successful 'all files' operation",
          vcr: {cassette_name: "openai/vector_stores/successful_all_files"} do
    let(:store) { provider.vector_stores.create_and_poll(name: "test store", file_ids: [file.id], interval:) }
    let(:file) { provider.files.create(file: "spec/fixtures/documents/haiku1.txt") }
    subject { provider.vector_stores.all_files(vector: store) }
    after do
      provider.vector_stores.delete(vector: store)
      provider.files.delete(file:)
    end

    it "is successful" do
      is_expected.to be_ok
    end

    it "includes data array" do
      is_expected.to have_attributes(
        "data" => be_an(Array)
      )
    end
  end

  context "when given a successful 'add file' operation",
          vcr: {cassette_name: "openai/vector_stores/successful_add_file"} do
    let(:store) { provider.vector_stores.create_and_poll(name: "test store", file_ids: [file1.id], interval:) }
    let(:file1) { provider.files.create(file: "spec/fixtures/documents/haiku1.txt") }
    let(:file2) { provider.files.create(file: "spec/fixtures/documents/readme.md") }
    subject { provider.vector_stores.add_file(vector: store, file: file2) }

    after do
      provider.vector_stores.delete(vector: store)
      provider.files.delete(file: file1)
      provider.files.delete(file: file2)
    end

    it "is successful" do
      is_expected.to be_ok
    end

    it "returns the file" do
      is_expected.to have_attributes(
        "id" => instance_of(String)
      )
    end
  end

  context "when given a successful 'update file' operation",
          vcr: {cassette_name: "openai/vector_stores/successful_update_file"} do
    let(:store) { provider.vector_stores.create_and_poll(name: "test store", interval:) }
    let(:file) { provider.files.create(file: "spec/fixtures/documents/haiku1.txt") }
    subject { provider.vector_stores.update_file(vector: store, file:, attributes: {tag: "updated"}) }

    before do
      provider.vector_stores.add_file_and_poll(vector: store, file:, interval:)
    end

    after do
      provider.vector_stores.delete(vector: store)
      provider.files.delete(file:)
    end

    it "is successful" do
      is_expected.to be_ok
    end

    it "returns the file" do
      is_expected.to have_attributes(
        "id" => file.id,
        "attributes" => have_attributes("tag" => "updated")
      )
    end
  end

  context "when given a successful 'get file' operation",
          vcr: {cassette_name: "openai/vector_stores/successful_get_file"} do
    let(:store) { provider.vector_stores.create_and_poll(name: "test store", interval:) }
    let(:file) { provider.files.create(file: "spec/fixtures/documents/haiku1.txt") }
    subject { provider.vector_stores.get_file(vector: store, file:) }

    before do
      provider.vector_stores.add_file_and_poll(vector: store, file:, interval:)
    end

    after do
      provider.vector_stores.delete(vector: store)
      provider.files.delete(file:)
    end

    it "is successful" do
      is_expected.to be_ok
    end

    it "returns the file" do
      is_expected.to have_attributes(
        "id" => file.id
      )
    end
  end

  context "when given a successful 'delete file' operation",
          vcr: {cassette_name: "openai/vector_stores/successful_delete_file"} do
    let(:store) { provider.vector_stores.create_and_poll(name: "test store", file_ids: [file.id], interval:) }
    let(:file) { provider.files.create(file: "spec/fixtures/documents/haiku1.txt") }
    subject { provider.vector_stores.delete_file(vector: store, file:) }

    after do
      provider.vector_stores.delete(vector: store)
      provider.files.delete(file:)
    end

    it "is successful" do
      is_expected.to be_ok
    end

    it "returns deleted status" do
      is_expected.to have_attributes(
        "deleted" => true
      )
    end
  end

  context "when given a 'search' operation that returns no results",
          vcr: {cassette_name: "openai/vector_stores/successful_search_no_results"} do
    let(:store) { provider.vector_stores.create_and_poll(name: "test store", interval:) }
    subject(:chunks) { provider.vector_stores.search(vector: store, query: "nonexistent query") }

    after do
      provider.vector_stores.delete(vector: store)
    end

    it "is successful" do
      is_expected.to be_ok
    end

    it "is empty" do
      is_expected.to be_empty
    end

    it "has size zero" do
      expect(chunks.size).to be_zero
    end
  end

  def interval
    VCR.current_cassette&.recording? ? 5 : 0
  end
end
