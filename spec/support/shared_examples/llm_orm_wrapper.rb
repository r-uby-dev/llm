# frozen_string_literal: true

RSpec.shared_examples "a persisted llm record" do
  it "resolves a provider instance from the record" do
    expect(record.llm).to be_a(LLM::Provider)
    expect(record.llm).to be_a(LLM::OpenAI)
    expect(record.llm.tracer).to be_a(LLM::Tracer::Logger)
  end

  it "reads usage from the runtime state" do
    expect(record.usage.total_tokens).to eq(0)
  end

  it "persists through #talk",
     vcr: {cassette_name: "openai/chat/completion_contract"} do
    expect(record.talk("Hello, world!")).to be_a(LLM::Response)
    expect(reload_record.call(record).messages.last).to be_a(LLM::Message)
    expect(reload_record.call(record).messages.last.content).not_to be_empty
  end

  it "persists through #ask",
     vcr: {cassette_name: "openai/chat/completion_contract"} do
    expect(record.ask("Hello, world!")).to be_a(LLM::Response)
    expect(reload_record.call(record).messages.last).to be_a(LLM::Message)
    expect(reload_record.call(record).messages.last.content).not_to be_empty
  end

  it "persists runtime state on the same row" do
    runtime = LLM::Test::Runtime.new
    runtime.messages << LLM::Message.new("user", "hello")
    record.instance_variable_set(:@ctx, runtime)
    flush_record.call(record)
    expect(reload_record.call(record).messages.map(&:content)).to eq(["hello"])
  end
end

RSpec.shared_examples "a persisted context record" do
  include_examples "a persisted llm record"

  it "restores an LLM::Context runtime" do
    expect(record.send(:ctx)).to be_a(LLM::Context)
    expect(record.send(:ctx).params[:store]).to be(false)
  end
end

RSpec.shared_examples "a persisted agent record" do
  include_examples "a persisted llm record"

  it "restores an LLM::Agent runtime" do
    expect(record.send(:ctx)).to be_a(LLM::Agent)
    expect(record.send(:ctx).mode).to eq(:responses)
  end

  it "reads agent defaults from the model class" do
    expect(record.class.agent.model).to eq("gpt-5.4-mini")
    expect(record.class.agent.instructions).to eq("You are concise.")
    expect(record.class.agent.concurrency).to eq(:thread)
  end

  it "resolves an agent field declared as a symbol against the record" do
    expect(record.send(:ctx).description).to eq("described by the model")
  end
end

