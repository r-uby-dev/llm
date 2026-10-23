# frozen_string_literal: true

RSpec.shared_examples "LLM::Context: files" do |dirname, options = {}|
  filepath = options.delete(:fixture)  || "spec/fixtures/documents/haiku1.txt"
  question = options.delete(:question) || "Does this file mention the moon?"
  vcr      = lambda do |basename|
    {vcr: {cassette_name: "#{dirname}/chat/#{basename}"}.merge(options)}
  end

  context "when a file is uploaded and referenced",
          vcr.call("llm_file_upload_reference") do
    subject { ctx.messages.find(&:assistant?).content.downcase[0..2] }

    let(:params) { super() }
    let(:file) { provider.files.create(file: filepath) }
    let(:prompt) do
      [
        question,
        "Answer with yes or no",
        "Nothing else",
        ctx.remote_file(file)
      ]
    end

    before { ctx.talk(prompt) }

    it "sees the file it was given" do
      is_expected.to eq("yes")
    ensure
      provider.files.delete(file:)
    end
  end
end

