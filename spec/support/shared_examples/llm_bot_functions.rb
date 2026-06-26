# frozen_string_literal: true

RSpec.shared_examples "LLM::Context: functions" do |dirname, options = {}|
  vcr = lambda do |basename|
    {vcr: {cassette_name: "#{dirname}/chat/#{basename}"}.merge(options)}
  end

  shared_examples "system" do |request|
    let(:params) { {tools: [tool]} }
    let(:returns) { ctx.messages.select(&:tool_return?) }
    let(:prompt) do
      ctx.build_prompt do
        _1.user "You are a bot that can run UNIX commands"
        _1.user request
      end
    end

    before { ctx.talk(prompt) }

    it "calls the function" do
      expect(Kernel).to receive(:system).with("date").and_return("2025-08-24")
      ctx.talk ctx.functions[0].call
      expect(ctx.functions).to be_empty
    end

    it "calls the function" do
      expect(Kernel).to receive(:system).with("date").and_return("2025-08-24")
      ctx.talk ctx.functions.map(&:call)
      expect(ctx.functions).to be_empty
    end

    it "includes a message with a return value" do
      allow(Kernel).to receive(:system).with("date").and_return("2025-08-24")
      ctx.talk ctx.functions.map(&:call)
      expect(returns.size).to be(1)
    end
  end

  shared_examples "system: multiple" do |request|
    let(:tool) do
      LLM.function(:system) do |fn|
        fn.description "Run a shell command"
        fn.params do |schema|
          schema.object(command: schema.string.required)
        end
        fn.define do |command:|
          ro, wo = IO.pipe
          re, we = IO.pipe
          Process.wait Process.spawn(command, out: wo, err: we)
          [wo,we].each(&:close)
          {stderr: re.read, stdout: ro.read}
        end
      end
    end
    let(:params) { {tools: [tool]} }
    let(:returns) { ctx.messages.select(&:tool_return?) }
    let(:prompt) do
      ctx.build_prompt do
        _1.user "You are a bot that can run UNIX commands"
        _1.user request
      end
    end

    before { ctx.talk(prompt) }

    it "calls the functions" do
      i = 0
      until ctx.functions.empty?
        raise "Too many iterations, something is wrong" if i == 3
        ctx.talk ctx.functions.map(&:call)
        i += 1
      end
      expect(ctx.functions).to be_empty
    end
  end

  context "with a block", vcr.call("llm_function_block") do
    let(:tool) do
      LLM.function(:system) do |fn|
        fn.description "Runs system commands"
        fn.params { _1.object(command: _1.string.required) }
        fn.define { |command:| {success: Kernel.system(command.chomp)} }
      end
    end
    include_examples "system", "What is the date?"
  end

  context "with a class", vcr.call("llm_function_class") do
    let(:tool) do
      Class.new(LLM::Tool) do
        name "system"
        description "Runs system commands"
        params { _1.object(command: _1.string.required) }
        def call(command:)
          {success: Kernel.system(command.chomp)}
        end
      end
    end
    include_examples "system", "What is the date?"
  end

  context "with multiple calls", vcr.call("llm_function_multiple") do
    include_examples "system: multiple",
                     "Can you run the date command ? " \
                     "Can you run the pwd command ? " \
                     "Can you run the whoami command ?"
  end
end
