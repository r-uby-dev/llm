# frozen_string_literal: true

require "setup"

RSpec.describe LLM::Intercept do
  let(:provider) { LLM.openai(key: "test") }
  let(:ctx) { LLM::Context.new(provider) }
  let(:tool) do
    Class.new(LLM::Tool) do
      name "echo"
      description "Echo a value"
      param :value, String, "Value", required: true
      def call(value:) = {value:}
    end
  end
  let(:function) { tool.function.tap { |fn| fn.id = "call_1" } }
  let(:null_intercept) { LLM::Intercept::Null.new(provider) }
  let(:result) { null_intercept.call(function:) }

  describe LLM::Intercept::Null do
    it "never blocks" do
      expect(result).to be_nil
    end

    ##
    # An intercept is built with a provider and the context is attached to
    # it by the context that wired it, so what `#intercept` returns is an
    # instance rather than the class it was configured with.
    it "is the default intercept" do
      expect(ctx.intercept).to be_a(LLM::Intercept::Null)
    end

    it "carries the context it was wired to" do
      expect(ctx.intercept.send(:context)).to equal(ctx)
    end
  end

  describe "context wiring" do
    let(:blocking) do
      Class.new(LLM::Intercept) do
        def call(function:, **)
          "stop"
        end
      end
    end
    let(:wired) { LLM::Context.new(provider, intercept: blocking) }

    it "keeps a custom intercept class" do
      expect(wired.intercept).to be_a(blocking)
    end
  end

  describe "intercept options" do
    let(:seen) { [] }
    let(:intercept) do
      seen = self.seen
      Class.new(LLM::Intercept) do
        define_method(:call) do |function:, **opts|
          seen << opts[:threshold]
          nil
        end
      end
    end
    let(:ctx) { LLM::Context.new(provider, intercept:, intercept_options: {threshold: 5}) }
    let(:called) { ctx.intercept.call(function:, **ctx.instance_variable_get(:@intercept)[:options]) }

    before { called }

    it "passes intercept_options to the intercept" do
      expect(seen).to eq([5])
    end
  end
end
