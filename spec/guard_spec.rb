# frozen_string_literal: true

require "setup"

RSpec.describe LLM::Guard do
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
  let(:null_guard) { LLM::Guard::Null.new(provider) }
  let(:result) { null_guard.call(function:) }

  describe LLM::Guard::Null do
    it "never blocks" do
      expect(result).to be_nil
    end

    ##
    # A guard is built with a provider and the context is attached to it
    # by the context that wired it, so what `#guard` answers is an
    # instance rather than the class it was configured with.
    it "is the default guard" do
      expect(ctx.guard).to be_a(LLM::Guard::Null)
    end

    it "carries the context it was wired to" do
      expect(ctx.guard.send(:context)).to equal(ctx)
    end
  end

  describe "context wiring" do
    let(:blocking) do
      Class.new(LLM::Guard) do
        def call(function:, **)
          "stop"
        end
      end
    end
    let(:wired) { LLM::Context.new(provider, guard: blocking) }

    it "keeps a custom guard class" do
      expect(wired.guard).to be_a(blocking)
    end
  end

  describe "guard options" do
    let(:seen) { [] }
    let(:guard) do
      seen = self.seen
      Class.new(LLM::Guard) do
        define_method(:call) do |function:, **opts|
          seen << opts[:threshold]
          nil
        end
      end
    end
    let(:ctx) { LLM::Context.new(provider, guard:, guard_options: {threshold: 5}) }
    let(:called) { ctx.guard.call(function:, **ctx.instance_variable_get(:@guard)[:options]) }

    before { called }

    it "passes guard_options to the guard" do
      expect(seen).to eq([5])
    end
  end
end
