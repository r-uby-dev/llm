# frozen_string_literal: true

require "setup"

RSpec.describe LLM::Schema::Parser do
  describe ".parse" do
    subject(:parse) { LLM::Schema.parse(schema) }

    context "when given an object schema" do
      let(:schema) do
        {
          type: "object",
          description: "person",
          properties: {
            name: {type: "string", description: "name"},
            tags: {
              type: "array",
              items: {type: "string", minLength: 2}
            }
          },
          required: ["name"]
        }
      end

      it "returns an object schema" do
        expect(parse).to be_a(LLM::Schema::Object)
      end

      it "parses nested properties" do
        expect(parse["name"]).to be_a(LLM::Schema::String)
        expect(parse["name"].description).to eq("name")
      end

      it "marks required properties" do
        expect(parse["name"]).to be_required
        expect(parse["tags"]).to_not be_required
      end

      it "parses nested array items" do
        array = parse["tags"]
        expect(array).to be_a(LLM::Schema::Array)
        expect(array.to_h[:type]).to eq("array")
        expect(array.to_h[:items]).to eq(
          LLM::Schema.new.string.min(2)
        )
      end
    end

    context "when given an array schema" do
      let(:schema) do
        {
          type: "array",
          description: "directories",
          items: {
            type: "object",
            properties: {
              path: {type: "string"},
              size: {type: "integer", minimum: 0}
            },
            required: ["path"]
          }
        }
      end

      it "returns an array schema" do
        expect(parse).to be_a(LLM::Schema::Array)
      end

      it "parses the array metadata" do
        expect(parse.to_h[:description]).to eq("directories")
        expect(parse.to_h[:type]).to eq("array")
      end

      it "parses item schemas recursively" do
        item = parse.to_h[:items]
        expect(item).to be_a(LLM::Schema::Object)
        expect(item.keys).to eq(%w[path size])
        expect(item["path"]).to be_required
        expect(item["path"]).to eq(LLM::Schema.new.string)
        expect(item["size"]).to eq(LLM::Schema.new.integer.min(0))
      end
    end

    context "when given an anyOf union" do
      let(:schema) do
        {
          anyOf: [
            {type: "string", minLength: 1},
            {type: "array", items: {type: "string"}}
          ],
          description: "input"
        }
      end

      it "returns an anyOf schema" do
        expect(parse).to be_a(LLM::Schema::AnyOf)
      end

      it "parses each branch recursively" do
        expect(parse.to_h).to eq(
          description: "input",
          anyOf: [
            LLM::Schema.new.string.min(1),
            LLM::Schema.new.array(LLM::Schema.new.string)
          ]
        )
      end
    end

    context "when given a type array union" do
      let(:schema) do
        {
          type: ["object", "null"],
          description: "maybe object",
          properties: {
            id: {type: "string"}
          },
          required: ["id"]
        }
      end

      it "returns an anyOf schema" do
        expect(parse).to be_a(LLM::Schema::AnyOf)
      end

      it "parses each branch recursively" do
        expect(parse.to_h).to eq(
          description: "maybe object",
          anyOf: [
            LLM::Schema.new.object("id" => LLM::Schema.new.string.required),
            LLM::Schema.new.null
          ]
        )
      end
    end

    context "when type is omitted but const implies a primitive" do
      let(:schema) do
        {
          const: "workspace",
          description: "kind"
        }
      end

      it "infers the primitive type" do
        expect(parse).to eq(
          LLM::Schema.new.string.const("workspace").description("kind")
        )
      end
    end

    context "when given a oneOf union" do
      let(:schema) do
        {
          oneOf: [
            {type: "string"},
            {type: "integer", minimum: 1}
          ],
          description: "choice"
        }
      end

      it "returns a oneOf schema" do
        expect(parse).to be_a(LLM::Schema::OneOf)
      end

      it "parses each branch recursively" do
        expect(parse.to_h).to eq(
          description: "choice",
          oneOf: [
            LLM::Schema.new.string,
            LLM::Schema.new.integer.min(1)
          ]
        )
      end
    end

    context "when given an allOf union" do
      let(:schema) do
        {
          allOf: [
            {type: "string", minLength: 1},
            {type: "string", maxLength: 10}
          ],
          description: "constrained"
        }
      end

      it "returns an allOf schema" do
        expect(parse).to be_a(LLM::Schema::AllOf)
      end

      it "parses each branch recursively" do
        expect(parse.to_h).to eq(
          description: "constrained",
          allOf: [
            LLM::Schema.new.string.min(1),
            LLM::Schema.new.string.max(10)
          ]
        )
      end
    end

    context "when given scalar metadata" do
      let(:schema) do
        {
          type: "number",
          description: "ratio",
          default: 1,
          enum: [1, 2],
          minimum: 0,
          maximum: 10
        }
      end

      it "applies metadata to the parsed leaf" do
        expect(parse.to_h).to eq(
          description: "ratio",
          default: 1,
          enum: [1, 2],
          type: "number",
          minimum: 0,
          maximum: 10
        )
      end
    end

    context "when given local refs" do
      let(:schema) do
        {
          type: "object",
          properties: {
            owner: {type: "string", description: "owner"},
            collaborator: {"$ref" => "#/properties/owner", :description => "collaborator"}
          },
          required: ["collaborator"]
        }
      end

      it "resolves the ref against the root schema" do
        expect(parse["collaborator"]).to be_a(LLM::Schema::String)
        expect(parse["collaborator"].description).to eq("collaborator")
        expect(parse["collaborator"]).to be_required
      end
    end

    context "when importing local reference chains" do
      let(:schema) do
        {
          "type" => "object",
          "$defs" => {
            "Identifier" => {"type" => "string", "minLength" => 1, "description" => "base"},
            "DocumentId" => {"$ref" => "#/$defs/Identifier", "description" => "alias", "maxLength" => 8}
          },
          "properties" => {"id" => {"$ref" => "#/$defs/DocumentId", "description" => "site"}},
          "required" => ["id"]
        }
      end

      it "resolves aliases while retaining referencing-site metadata and required flags" do
        before = Marshal.dump(schema)
        expect(parse["id"].to_h).to eq(LLM::Schema.new.string.min(1).max(8).description("site").to_h)
        expect(Marshal.dump(schema)).to eq(before)
      end

      it "imports the same schema through a public MCP tool manifest" do
        client = LLM::MCP.http(url: "http://127.0.0.1:1")
        tool = LLM::Tool.mcp(client, {"name" => "lookup", "description" => "lookup", "inputSchema" => schema})
        expect(tool.function.params["id"]).to be_a(LLM::Schema::String)
        expect(tool.function.params["id"]).to be_required
        expect(tool.function.params["id"].to_h[:minLength]).to eq(1)
      end
    end

    {
      "document/id" => "document~1id",
      "document~id" => "document~0id",
      "~1" => "~01",
      "" => ""
    }.each do |name, token|
      it "resolves the JSON Pointer token #{token.inspect}" do
        schema = {"$defs" => {name => {"type" => "string"}}, "$ref" => "#/$defs/#{token}"}
        expect(LLM::Schema.parse(schema)).to be_a(LLM::Schema::String)
      end
    end

    {"document id" => "document%20id", "c%d" => "c%25d", "%2F" => "%252F", "+" => "+"}.each do |name, token|
      it "decodes the URI fragment #{token.inspect} once without treating plus as space" do
        schema = {"$defs" => {name => {"type" => "string"}}, "$ref" => "#/$defs/#{token}"}
        expect(LLM::Schema.parse(schema)).to be_a(LLM::Schema::String)
      end
    end

    ["00", "-1", "-", "bad"].each do |index|
      it "rejects an invalid array reference index #{index}" do
        schema = {"$defs" => {"choices" => [{"type" => "string"}]}, "$ref" => "#/$defs/choices/#{index}"}
        expect { LLM::Schema.parse(schema) }.to raise_error(TypeError, /unresolvable/)
      end
    end

    it "resolves an empty token immediately beneath the document root" do
      schema = {"" => {"type" => "string"}, "$ref" => "#/"}
      expect(LLM::Schema.parse(schema)).to be_a(LLM::Schema::String)
    end

    it "resolves a schema inside a union array" do
      schema = {"$defs" => {"Choice" => {"anyOf" => [{"type" => "string"}]}}, "$ref" => "#/$defs/Choice/anyOf/0"}
      expect(LLM::Schema.parse(schema)).to be_a(LLM::Schema::String)
    end

    it "rejects a pure alias cycle" do
      schema = {"$defs" => {"A" => {"$ref" => "#/$defs/B"}, "B" => {"$ref" => "#/$defs/A"}}, "$ref" => "#/$defs/A"}
      expect { LLM::Schema.parse(schema) }.to raise_error(TypeError)
    end

    [nil, 4, "https://example.invalid/schema", "#/$defs/missing", "#/$defs/name/type"].each do |ref|
      it "rejects an unsupported or unresolvable reference #{ref.inspect}" do
        schema = {"$defs" => {"name" => {"type" => "string"}}, "$ref" => ref}
        expect { LLM::Schema.parse(schema) }.to raise_error(TypeError)
      end
    end

    context "when given an unsupported schema type" do
      let(:schema) { {type: "nope"} }

      it "raises a type error" do
        expect { parse }.to raise_error(TypeError, /unsupported schema type/)
      end
    end
  end
end
