# frozen_string_literal: true

require "setup"

RSpec.describe LLM::Intercept::Rescue do
  let(:provider) { LLM.openai(key: "test") }
  let(:tool) do
    Class.new(LLM::Tool) do
      name "echo"
      description "Echo a value"

      def call(value:)
        "echo: #{value}"
      end
    end
  end
  let(:function) do
    tool.function.dup.tap do |fn|
      fn.id = "call_1"
      fn.arguments = {"value" => "hi"}
    end
  end
  let(:crashing) do
    Class.new(LLM::Intercept) do
      def call(function:, **)
        raise "boom"
      end
    end
  end
  let(:interrupting) do
    Class.new(LLM::Intercept) do
      def call(function:, **)
        raise LLM::Interrupt.new
      end
    end
  end

  it "prepends itself to every subclass" do
    expect(crashing.ancestors).to include(described_class)
  end

  it "returns a tool return when the intercept raises" do
    expect(crashing.new(provider).call(function:)).to be_error
  end

  it "names the error after the exception" do
    expect(crashing.new(provider).call(function:).value[:type]).to eq("RuntimeError")
  end

  it "reports the crash on standard error" do
    expect { crashing.new(provider).call(function:) }
      .to output(/has crashed/).to_stderr
  end

  it "lets an interrupt through" do
    expect { interrupting.new(provider).call(function:) }.to raise_error(LLM::Interrupt)
  end
end
