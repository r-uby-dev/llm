# frozen_string_literal: true

require "setup"

RSpec.describe LLM::Guard::Multi do
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
  let(:guards) { [passing] }
  let(:multi) { LLM::Guard.multi(provider, *guards) }
  let(:result) { multi.call(function:, context: ctx) }

  ##
  # Each guard records that it ran, so an example can say what the chain
  # did rather than what it returned alone.
  let(:passing) do
    order = self.order
    Class.new(LLM::Guard) do
      define_method(:call) do |function:, **|
        order << :passing
        nil
      end
    end
  end
  let(:blocking) do
    order = self.order
    Class.new(LLM::Guard) do
      define_method(:call) do |function:, **|
        order << :blocking
        function.return(error: true, type: "guard_error", message: "stop")
      end
    end
  end
  let(:never) do
    order = self.order
    Class.new(LLM::Guard) do
      define_method(:call) do |function:, **|
        order << :never
        nil
      end
    end
  end

  describe "a guard that passes" do
    before { result }

    it "answers nil" do
      expect(result).to be_nil
    end

    it "is run" do
      expect(order).to eq(%i[passing])
    end
  end

  describe "a guard chain that answers" do
    let(:guards) { [passing, blocking] }

    before { result }

    it "answers the first return a guard in it gives" do
      expect(result.value[:message]).to eq("stop")
    end

    it "runs the guards in the order they were given" do
      expect(order).to eq(%i[passing blocking])
    end
  end

  describe "a guard chain with a guard after the one that blocks" do
    let(:guards) { [passing, blocking, never] }

    before { result }

    it "stops at the guard that blocks" do
      expect(order).to eq(%i[passing blocking])
    end
  end
end
