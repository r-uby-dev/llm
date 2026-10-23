# frozen_string_literal: true

RSpec.shared_examples "LLM::Agent: skill" do |dirname, options = {}|
  vcr = lambda do |basename|
    {vcr: {cassette_name: "#{dirname}/chat/#{basename}"}.merge(options)}
  end

  context "when given a skill", vcr.call("llm_chat_skill_stream") do
    let(:events) { [] }
    let(:stream) do
      events = self.events
      Class.new(LLM::Stream) do
        define_method(:on_skill_call) do |skill|
          events << [:call, skill.name]
        end
        define_method(:on_skill_return) do |agent, skill, result|
          events << [:return, skill.name, result, agent]
        end
      end.new
    end
    let(:tool) do
      Class.new(LLM::Tool) do
        name "weather"
        description "Get the current weather"

        def call(**)
          {content: "sunny"}
        end
      end
    end
    let(:path) do
      dirname = File.join(Dir.tmpdir, "skills_spec_#{Process.pid}")
      File.join(dirname, "weather.md")
    end
    let(:params) { {skills: [path], tools: [tool], stream:} }
    let(:agent) { LLM::Agent.new(llm, params) }
    let(:run) { agent.talk("What's the weather?") }

    before do
      FileUtils.mkdir_p(File.dirname(path))
      File.write(path, <<~MD)
        ---
        name: weather
        description: Get the current weather
        tools:
          - weather
        ---
        Use the weather tool to report the current weather.
      MD
    end

    context "when given callbacks" do
      context "when given on_skill_call" do
        it "calls the method" do
          run
          expect(events[0][0]).to eq(:call)
        end

        it "forwards the skill name" do
          run
          expect(events[0][1]).to eq("weather")
        end
      end

      context "when given on_skill_return" do
        it "calls the method" do
          run
          expect(events[1][0]).to eq(:return)
        end

        it "forwards the skill name" do
          run
          expect(events[1][1]).to eq("weather")
        end

        it "forwards an LLM::Response" do
          run
          expect(events[1][2]).to be_a(LLM::Response)
        end

        it "forwards an LLM::Agent" do
          run
          expect(events[1][3]).to be_a(LLM::Agent)
        end
      end
    end

    context "when given an agent" do
      it "it contains a response" do
        run
        expect(agent.messages.size).to be >= 2
      end
    end
  end
end

