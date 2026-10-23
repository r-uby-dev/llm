# frozen_string_literal: true

RSpec.shared_examples "LLM::Context: schema" do |dirname, options = {}|
  vcr = lambda do |basename|
    {vcr: options.merge({cassette_name: "#{dirname}/chat/#{basename}"})}
  end

  shared_examples "schema: given an object" do |schema:|
    context do
      let(:params) { {schema:} }
      let(:llm) { provider }

      subject { ctx.messages.find(&:assistant?).content! }

      before do
        ctx.talk "Return probability 1 for true and 0 for false. Does the earth orbit the sun?"
      end

      it "returns the probability" do
        is_expected.to match(
          "probability" => instance_of(Integer)
        )
      end
    end
  end

  shared_examples "schema: given an enum" do |schema:|
    context do
      let(:params) { {schema:} }
      let(:llm) { provider }

      subject { ctx.messages.find(&:assistant?).content!  }

      let(:prompt) do
        ctx.build_prompt do |prompt|
          prompt.user "Your favorite fruit is pineapple"
          prompt.user "What fruit is your favorite?"
        end
      end

      before { ctx.talk(prompt) }

      it "returns the favorite fruit" do
        is_expected.to match(
          "fruit" => "pineapple"
        )
      end
    end
  end

  shared_examples "schema: given an array" do |schema:|
    context do
      let(:params) { {schema:} }
      let(:llm) { provider }

      subject { ctx.messages.find(&:assistant?).content! }

      let(:prompt) do
        ctx.build_prompt do |prompt|
          prompt.user "Return the numbers 10 and 12"
          prompt.user "Keep them in the same order"
        end
      end

      before { ctx.talk(prompt) }

      it "returns the answers" do
        is_expected.to match(
          "answers" => [10, 12]
        )
      end
    end
  end

  context "when given an object", vcr.call("llm_schema_object") do
    schema = LLM::Schema.new
    object = schema.object(
      probability: schema.integer.required.description("The answer's probability")
    )
    klass = Class.new(LLM::Schema) do
      property :probability, Integer, "The answer's probability", required: true
    end
    [object, klass].each do |schema|
      include_examples "schema: given an object", schema:
    end
  end

  context "when given an enum", vcr.call("llm_schema_enum") do
    schema = LLM::Schema.new
    object = schema.object(
      fruit: schema.string.enum("apple", "pineapple", "orange").required.description("The favorite fruit")
    )
    klass = Class.new(LLM::Schema) do
      property :fruit, String, "The favorite fruit", enum: ["apple", "pineapple", "orange"], required: true
    end
    [object, klass].each do |schema|
      include_examples "schema: given an enum", schema:
    end
  end

  context "when given an array", vcr.call("llm_schema_array") do
    schema = LLM::Schema.new
    object = schema.object(
      answers: schema.array(schema.integer.required).required.description("The answer to two questions")
    )
    klass = Class.new(LLM::Schema) do
      property :answers, LLM::Schema::Array[LLM::Schema::Integer], "The answer to two questions", required: true
    end
    [object, klass].each do |schema|
      include_examples "schema: given an array", schema:
    end
  end
end

