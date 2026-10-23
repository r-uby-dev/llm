# frozen_string_literal: true

require "setup"

class DeferredSpecTool < LLM::Tool
  name "fruit"
  parameter :fruit, proc { Enum["apple", "orange", "pineapple"] }, "A fruit"
  required %i[fruit]
end

class DeferredSpecSchema < LLM::Schema
  property :fruit, proc { Enum["apple", "orange"] }, "A fruit"
  required %i[fruit]
end

RSpec.describe LLM::Schema::Deferred do
  describe "when given as a tool parameter" do
    let(:parameters) { DeferredSpecTool.function.params }
    let(:fruit) { parameters.properties[:fruit].to_h }

    it "resolves the type the proc returns" do
      expect(fruit[:type]).to eq("string")
    end

    it "resolves the enum the proc returns" do
      expect(fruit[:enum]).to eq(%w[apple orange pineapple])
    end

    it "keeps the description given with the parameter" do
      expect(fruit[:description]).to eq("A fruit")
    end

    it "keeps the parameter required" do
      expect(parameters.properties[:fruit]).to be_required
    end

    it "resolves to the leaf the enum names" do
      expect(fruit[:type]).to eq(LLM::Schema::Enum["apple"].to_h[:type])
    end
  end

  describe "when given as a schema property" do
    let(:rendered) { LLM::Schema::Utils.close(DeferredSpecSchema.object) }
    let(:fruit) { rendered[:properties]["fruit"] }

    it "resolves the type the proc returns" do
      expect(fruit[:type]).to eq("string")
    end

    it "resolves the enum the proc returns" do
      expect(fruit[:enum]).to eq(%w[apple orange])
    end

    it "keeps the property required" do
      expect(rendered[:required]).to eq(["fruit"])
    end
  end

  describe "when the proc returns a type name" do
    let(:tool) do
      Class.new(LLM::Tool) do
        name "greeter"
        parameter :name, proc { String }, "A name", required: true
      end
    end
    let(:name) { tool.function.params.properties[:name].to_h }

    it "resolves String to the schema's String, not Ruby's" do
      expect(LLM::Tool::String).to be(LLM::Schema::String)
    end

    it "resolves the leaf the name stands for" do
      expect(name[:type]).to eq(LLM::Schema::String.new.to_h[:type])
    end
  end

  describe "when the type is only known at runtime" do
    let(:calls) { [] }
    let(:tool) do
      calls = self.calls
      Class.new(LLM::Tool) do
        name "fruit"
        parameter :fruit, proc { calls << :evaluated; LLM::Schema.new.string }, "A fruit"
      end
    end

    it "does not call the proc when the class is defined" do
      tool
      expect(calls).to be_empty
    end

    it "does not call the proc when the parameters are read" do
      tool.function.params
      expect(calls).to be_empty
    end

    it "calls the proc when the schema is rendered" do
      LLM::Schema::Utils.close(tool.function.params)
      expect(calls).to eq([:evaluated])
    end
  end
end
