# frozen_string_literal: true

RSpec.shared_examples "LLM::Context: text stream" do |dirname, options = {}|
  vcr = lambda do |basename|
    {vcr: {cassette_name: "#{dirname}/chat/#{basename}"}.merge(options)}
  end

  context "when given an IO stream", vcr.call("llm_chat_stream_stringio") do
    let(:params) { {stream:} }
    let(:stream) { StringIO.new }
    let(:system_prompt) do
      "Keep your answers short and concise, and provide three answers to the three questions. " \
      "There should be one answer per line. " \
      "An answer should be a number, for example: 5. " \
      "Nothing else"
    end
    let(:prompt) do
      ctx.build_prompt do
        _1.user system_prompt
        _1.user "What is 3+2 ?"
        _1.user "What is 5+5 ?"
        _1.user "What is 5+7 ?"
      end
    end

    before { ctx.talk(prompt) }

    context "with the contents of the IO" do
      subject { stream.string }
      it { is_expected.to match(%r_5\s*\n10\s*\n12\s*_) }
    end

    context "with the contents of the message" do
      subject { ctx.messages.find(&:assistant?) }
      it { is_expected.to have_attributes(role: %r_(assistant|model)_, content: %r_5\s*\n10\s*\n12\s*_ ) }
    end

    context "with usage" do
      subject(:usage) { ctx.messages.find(&:assistant?)&.usage }
      it { expect(usage.input_tokens).to be > 0 }
      it { expect(usage.output_tokens).to be > 0 }
      it { expect(usage.total_tokens).to be > 0 }
    end
  end
end

RSpec.shared_examples "LLM::Context: tool stream" do |dirname, options = {}|
  vcr = lambda do |basename|
    {vcr: {cassette_name: "#{dirname}/chat/#{basename}"}.merge(options)}
  end

  context "when given a tool call", vcr.call("llm_chat_stream_tool") do
    let(:params) { {stream: true, tools: [tool]} }
    let(:tool) do
      LLM.function(:system) do |fn|
        fn.description "Runs system commands"
        fn.params { _1.object(command: _1.string.required) }
        fn.define { |command:| {success: Kernel.system(command)} }
      end
    end
    let(:prompt) do
      ctx.build_prompt do
        _1.user "You are a bot that can run UNIX system commands"
        _1.user "Hey, run the 'date' command"
      end
    end

    before { ctx.talk(prompt) }

    it "calls the function(s)" do
      expect(Kernel).to receive(:system).with("date").and_return("2022-01-01")
      ctx.talk ctx.pending_functions.map(&:call)
      expect(ctx.pending_functions).to be_empty
    end
  end
end
