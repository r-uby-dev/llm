# frozen_string_literal: true

RSpec.shared_examples "inherited wrapper callbacks" do
  let(:superclass) do
    Class.new(model) do
      private

      def set_provider
        LLM.openai(key: "secret")
      end

      def set_context
        {mode: :responses, store: false}
      end
    end
  end

  let(:create_record) { ->(klass) { klass.respond_to?(:create!) ? klass.create! : klass.create } }
  let(:row) { create_record.call(wrapped) }

  context "when the callbacks are defined on a superclass" do
    let(:wrapped) { wrap.call(Class.new(superclass)) }

    it "resolves the provider from the superclass" do
      expect(row.llm).to be_a(LLM::OpenAI)
    end

    it "resolves the context params from the superclass" do
      expect(row.send(:ctx).params).to include(store: false)
    end
  end

  context "when a subclass overrides a callback" do
    let(:wrapped) do
      wrap.call(Class.new(superclass) do
        private

        def set_provider
          LLM.openrouter(key: "override")
        end
      end)
    end

    it "resolves the provider from the subclass" do
      expect(row.llm).to be_a(LLM::OpenRouter)
    end
  end

  context "when no callback is defined" do
    let(:wrapped) { wrap.call(model) }

    it "raises NotImplementedError" do
      expect { row.llm }.to raise_error(NotImplementedError, /set_provider/)
    end
  end
end
