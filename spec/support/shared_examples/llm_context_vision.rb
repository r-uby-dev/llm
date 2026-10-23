# frozen_string_literal: true

RSpec.shared_examples "LLM::Context: vision" do |dirname, options = {}|
  formats = options.delete(:formats) || %i[png pdf]
  vcr = lambda do |basename|
    {vcr: {cassette_name: "#{dirname}/chat/#{basename}"}.merge(options)}
  end

  context "when given a local pdf", vcr.call("llm_file_local_pdf") do
    subject { ctx.messages.find(&:assistant?).content.downcase[0..2] }
    before { ctx.talk(prompt) }

    let(:params) { super() }
    let(:pdf) { File.join(Dir.getwd, "spec", "fixtures", "documents", "freebsd.sysctl.pdf") }
    let(:prompt) do
      [
        "Does this PDF mention FreeBSD at all?",
        "Answer with yes or no",
        "Nothing else",
        ctx.local_file(pdf)
      ]
    end

    it "can analyze a PDF" do
      is_expected.to eq("yes")
    end
  end if formats.include?(:pdf)

  context "when given a local image", vcr.call("llm_file_local_image") do
    subject { ctx.messages.find(&:assistant?).content.downcase[0..2] }

    let(:params) { super() }
    let(:image) { "spec/fixtures/images/bluebook.png" }
    let(:array_prompt) do
      [
        "Could the image be a book ?",
        "If there is any chance, answer in the affirmative",
        "Answer with yes or no",
        "Nothing else",
        ctx.local_file(image)
      ]
    end
    let(:llm_prompt) do
      ctx.build_prompt do |p|
        array_prompt.each { p.talk(_1, role: :user) }
      end
    end

    context "when given as an array of messages" do
      before { ctx.talk(array_prompt) }

      it "can analyze an image" do
        is_expected.to eq("yes")
      end
    end

    context "when given as a LLM::Prompt" do
      before { ctx.talk(llm_prompt) }

      it "can analyze an image" do
        is_expected.to eq("yes")
      end
    end
  end if formats.include?(:png)
end

