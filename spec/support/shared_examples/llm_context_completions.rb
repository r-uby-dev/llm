# frozen_string_literal: true

RSpec.shared_examples "LLM::Context: completions" do |dirname, options = {}|
  vcr = lambda do |basename|
    {vcr: {cassette_name: "#{dirname}/chat/#{basename}"}.merge(options)}
  end

  context "when given a thread of messages", vcr.call("llm_chat_completions") do
    let(:system_prompt) do
      "Keep your answers short and concise, and provide three answers to the three questions" \
      "There should be one answer per line" \
      "An answer should be a number, for example: 5" \
      "Nothing else"
    end

    let(:messages) { ctx.messages }
    let(:message) { messages.to_a[-1] }
    let(:prompt) do
      ctx.build_prompt do
        _1.talk system_prompt
        _1.talk "What is 3+2 ?"
        _1.talk "What is 5+5 ?"
        _1.talk "What is 5+7 ?"
      end
    end

    before { ctx.talk(prompt) }

    it "provides a response" do
      expect(message).to have_attributes(
        role: %r_\A(assistant|model)\z_,
        content: %r_5\s*\n10\s*\n12\s*_
      )
    end

    it "provides an Enumerator" do
      expect(messages.each).to be_a(Enumerator)
    end

    it "provides a message at an index" do
      0.upto(4) { |i| expect(messages[i]).to be_a(LLM::Message) }
    end

    it "returns nil when an index is out of bounds" do
      expect(messages[5]).to be_nil
    end

    it "provides the 'last' message" do
      expect(messages.last).to eq(messages.to_a[-1])
    end
  end

  context "when given a prompt that is not recognized" do
    it "raises an error" do
      expect { ctx.talk(Object.new) }.to raise_error(LLM::PromptError)
    end
  end
end

