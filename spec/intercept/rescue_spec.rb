# frozen_string_literal: true

require "setup"

RSpec.describe LLM::Intercept::Rescue do
  let(:provider) { LLM.openai(key: "test") }
  let(:function) { nil }
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

  it "lets the tool call through when the intercept raises" do
    expect(crashing.new(provider).call(function:)).to be_nil
  end

  it "reports the crash on standard error" do
    expect { crashing.new(provider).call(function:) }
      .to output(/an llm.rb intercept has crashed/).to_stderr
  end

  it "lets an interrupt through" do
    expect { interrupting.new(provider).call(function:) }.to raise_error(LLM::Interrupt)
  end
end
