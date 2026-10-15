# frozen_string_literal: true

require "setup"

RSpec.describe LLM::Intercept::Multi do
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
  let(:order) { [] }
  let(:intercepts) { [passing] }
  let(:multi) { LLM::Intercept.multi(provider, *intercepts) }
  let(:result) { multi.call(function:, context: ctx) }

  ##
  # Each intercept records that it ran, so an example can say what the chain
  # did rather than what it returned alone.
  let(:passing) do
    order = self.order
    Class.new(LLM::Intercept) do
      define_method(:call) do |function:, **|
        order << :passing
        nil
      end
    end
  end
  let(:blocking) do
    order = self.order
    Class.new(LLM::Intercept) do
      define_method(:call) do |function:, **|
        order << :blocking
        function.return(error: true, type: "intercept_error", message: "stop")
      end
    end
  end
  let(:never) do
    order = self.order
    Class.new(LLM::Intercept) do
      define_method(:call) do |function:, **|
        order << :never
        nil
      end
    end
  end

  describe "an intercept that passes" do
    before { result }

    it "answers nil" do
      expect(result).to be_nil
    end

    it "is run" do
      expect(order).to eq(%i[passing])
    end
  end

  describe "an intercept chain that answers" do
    let(:intercepts) { [passing, blocking] }

    before { result }

    it "answers the first return an intercept in it gives" do
      expect(result.value[:message]).to eq("stop")
    end

    it "runs the intercepts in the order they were given" do
      expect(order).to eq(%i[passing blocking])
    end
  end

  describe "an intercept chain with an intercept after the one that blocks" do
    let(:intercepts) { [passing, blocking, never] }

    before { result }

    it "stops at the intercept that blocks" do
      expect(order).to eq(%i[passing blocking])
    end
  end
end
