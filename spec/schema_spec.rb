# frozen_string_literal: true

require_relative "setup"

RSpec.describe LLM::Schema do
  context "when given a schema" do
    let(:all_properties) { [*required_properties, *unrequired_properties] }
    let(:required_properties) { %w[name age height] }
    let(:unrequired_properties) { %w[active location addresses] }
    let(:default_properties) { %w[name age] }

    let(:schema) do
      Class.new(LLM::Schema) do
        property :name, LLM::Schema::String, "name description", required: true
        property :age, LLM::Schema::Integer, "age description", required: true
        property :height, LLM::Schema::Number, "height description", required: true
        property :active, LLM::Schema::Boolean, "active description"
        property :location, LLM::Schema::Null, "location description"
        property :addresses, LLM::Schema::Array[LLM::Schema::String], "addresses description"
        defaults(name: "john", age: 18)
      end
    end

    it "has properties" do
      expect(schema.object.keys).to eq(all_properties)
    end

    it "has defaults" do
      actual = schema.object.properties.select { _2.default }.keys
      expect(actual).to eq(default_properties)
    end

    it "sets properties" do
      all_properties.each { expect(schema.object[_1].description).to eq("#{_1} description") }
      required_properties.each { expect(schema.object[_1]).to be_required }
      unrequired_properties.each { expect(schema.object[_1]).to_not be_required }
    end

    it "configures an array" do
      array = schema.object["addresses"]
      schema = self.schema.schema
      expect(array).to eq(
        schema.array(schema.string).description("addresses description")
      )
    end

    it "serializes with the standard JSON generator" do
      skip "requires json gem" unless ENV["JSON_PARSER"] == "json"
      expect(JSON.dump(schema.object)).to include(%("properties"))
    end
  end

  context "when given a mixed Array[...] property type" do
    let(:schema) do
      Class.new(LLM::Schema) do
        property :values, Array[String, Integer], "mixed values", required: true
      end
    end

    context "when reading the values property" do
      subject(:values) { schema.object["values"] }

      it "builds an array property" do
        expect(values).to be_a(LLM::Schema::Array)
      end

      it "preserves the description" do
        expect(values.description).to eq("mixed values")
      end

      it "marks the property as required" do
        expect(values).to be_required
      end

      it "builds anyOf items" do
        expect(values.to_h[:items]).to eq(
          LLM::Schema.new.any_of(LLM::Schema.new.string, LLM::Schema.new.integer)
        )
      end
    end
  end

  context "when given nested schema classes" do
    let(:address_schema) do
      Class.new(LLM::Schema) do
        property :street, String, "street description", required: true
      end
    end

    let(:person_schema) do
      address = address_schema
      Class.new(LLM::Schema) do
        property :name, String, "name description", required: true
        property :address, address, "address description", required: true
      end
    end

    context "when given the address" do
      subject(:address) { person_schema.object["address"] }

      it "is configured properly" do
        expect(address).to be_a(LLM::Schema::Object)
        expect(address.description).to eq("address description")
        expect(address).to be_required
        expect(address.keys).to eq(["street"])
      end
    end

    context "when given the street" do
      subject(:street) { person_schema.object["address"]["street"] }

      it "is configured properly" do
        expect(street).to be_a(LLM::Schema::String)
        expect(street.description).to eq("street description")
        expect(street).to be_required
      end
    end

    it "requires certain keys" do
      object = person_schema.object
      expect(object.to_h[:required]).to eq(%w[name address])
      expect(object["address"].to_h[:required]).to eq(["street"])
    end
  end

  context "when required fields are declared separately" do
    let(:schema) do
      Class.new(LLM::Schema) do
        property :location, String, "location description"
        required %i[location]
      end
    end

    context "when reading the location property" do
      subject(:location) { schema.object["location"] }

      it "marks the property as required" do
        expect(location).to be_required
      end
    end

    context "when serializing the schema" do
      subject(:required_items) { schema.object.to_h[:required] }

      it "serializes the required field list" do
        expect(required_items).to eq(["location"])
      end
    end
  end

  context "when given a oneOf property type" do
    let(:schema) do
      eval(<<~RUBY, binding, __FILE__, __LINE__ + 1)
        class ResultSchema < LLM::Schema
          property :result, OneOf[String, Integer], "result description", required: true
        end
        ResultSchema
      RUBY
    end

    subject(:result) { schema.object["result"] }

    it "configures the property as a oneOf union" do
      expect(result).to be_a(LLM::Schema::OneOf)
      expect(result.description).to eq("result description")
      expect(result).to be_required
      expect(result.to_h[:oneOf].map(&:class)).to eq([LLM::Schema::String, LLM::Schema::Integer])
    end
  end

  context "when given an anyOf property type" do
    let(:schema) do
      eval(<<~RUBY, binding, __FILE__, __LINE__ + 1)
        class AnyResultSchema < LLM::Schema
          property :result, AnyOf[String, Integer], "result description", required: true
        end
        AnyResultSchema
      RUBY
    end

    subject(:result) { schema.object["result"] }

    it "configures the property as an anyOf union" do
      expect(result).to be_a(LLM::Schema::AnyOf)
      expect(result.description).to eq("result description")
      expect(result).to be_required
      expect(result.to_h[:anyOf].map(&:class)).to eq([LLM::Schema::String, LLM::Schema::Integer])
    end
  end

  context "when given an allOf property type" do
    let(:schema) do
      eval(<<~RUBY, binding, __FILE__, __LINE__ + 1)
        class AllResultSchema < LLM::Schema
          property :result, AllOf[String, Integer], "result description", required: true
        end
        AllResultSchema
      RUBY
    end

    subject(:result) { schema.object["result"] }

    it "configures the property as an allOf union" do
      expect(result).to be_a(LLM::Schema::AllOf)
      expect(result.description).to eq("result description")
      expect(result).to be_required
      expect(result.to_h[:allOf].map(&:class)).to eq([LLM::Schema::String, LLM::Schema::Integer])
    end
  end
end
