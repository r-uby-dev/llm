# frozen_string_literal: true

require "setup"

RSpec.describe LLM::Tool do
  before(:each) do
    described_class.clear_registry!
  end

  let(:shell) do
    Class.new(described_class) do
      name "shell"
      description "run shell commands"
    end
  end

  let(:weather) do
    Class.new(described_class) do
      name "weather"
      description "show a weather report"
    end
  end

  describe ".registry" do
    subject { described_class.registry }

    context "when given the shell tool" do
      before { shell }
      it { is_expected.to eq([shell]) }
    end

    context "when given the weather tool" do
      before { weather }
      it { is_expected.to eq([weather]) }
    end

    context "when given the weather and shell tools" do
      before { [weather, shell] }
      it { is_expected.to eq([weather, shell]) }
    end

    context "when given an inheritance chain" do
      let(:base) { Class.new(described_class) }
      let(:shell) do
        Class.new(base) do
          name "shell"
          description "run shell commands"
        end
      end

      before { [base, shell] }

      it "includes the tool with a definition" do
        is_expected.to eq([shell])
      end
    end

    context "when given an MCP tool" do
      let(:definition) do
        {
          "name" => "list_directory",
          "description" => "list a directory",
          "inputSchema" => {type: "object", properties: {}}
        }
      end
      let(:mcp_tool) { double("mcp tool", to_h: definition) }
      let(:mcp) { described_class.mcp(mcp_tool, definition) }
      before { mcp }

      it "includes it in the registry" do
        expect(subject.map(&:name)).to eq(["list_directory"])
      end
    end
  end

  describe ".unregister" do
    before { [weather, shell] }

    it "removes a tool from the registry" do
      described_class.unregister(shell)
      expect(described_class.registry).to eq([weather])
    end

    it "does nothing when the tool is not registered" do
      tool = Class.new(described_class)
      described_class.unregister(tool)
      expect(described_class.registry).to eq([weather, shell])
    end

    it "returns the unregistered tool" do
      expect(described_class.unregister(shell)).to eq(shell)
    end

    it "returns the given tool when it is not registered" do
      tool = Class.new(described_class)
      expect(described_class.unregister(tool)).to eq(tool)
    end
  end

  describe ".find_by_name" do
    before { [weather, shell] }

    it "returns a tool when found" do
      expect(described_class.find_by_name("shell")).to eq(shell)
    end

    it "returns nil when not found" do
      expect(described_class.find_by_name("missing")).to be_nil
    end
  end

  describe ".find_by_name!" do
    before { [weather, shell] }

    it "returns a tool when found" do
      expect(described_class.find_by_name!("shell")).to eq(shell)
    end

    it "raises when not found" do
      expect { described_class.find_by_name!("missing") }
        .to raise_error(LLM::NoSuchToolError, "tool 'missing' not found")
    end
  end

  describe ".function" do
    let(:provider) { LLM.xai(key: "TOKEN") }
    let(:parameters) { tool.function.adapt(provider)[:function][:parameters] }

    context "when given a tool with no arguments" do
      let(:tool) { shell }

      it "adapts the tool with a closed object schema" do
        expect(tool.function.adapt(provider)).to eq(
          type: "function",
          function: {
            name: "shell",
            description: "run shell commands",
            parameters: {
              type: "object",
              properties: {},
              required: [],
              additionalProperties: false
            },
            strict: false
          }
        )
      end

      it "closes the root object" do
        expect(parameters[:additionalProperties]).to be(false)
      end

      it "returns an empty schema hash" do
        expect(tool.function.params).to eq(LLM::Schema::Object.new({}))
      end
    end

    context "when given a tool with a nested object" do
      let(:tool) do
        schema = address
        Class.new(described_class) do
          name "person"
          description "a person"
          param :address, schema, "the address"
        end
      end
      let(:address) do
        Class.new(LLM::Schema) do
          property :street, String, "street"
          required %i[street]
        end
      end

      it "closes the nested object" do
        expect(parameters[:properties]["address"][:additionalProperties]).to be(false)
      end
    end
  end

  describe "#function" do
    let(:tool_class) do
      Class.new(described_class) do
        name "echo"

        def initialize(prefix:)
          @prefix = prefix
        end

        def call(value:)
          {"value" => "#{@prefix}: #{value}"}
        end
      end
    end
    let(:tool) { tool_class.new(prefix: "stateful") }

    it "returns a function bound to the tool instance" do
      result = tool.function.tap { it.arguments = {"value" => "hello"} }.call
      expect(result.to_h).to eq(
        id: nil,
        name: "echo",
        value: {"value" => "stateful: hello"}
      )
    end
  end

  describe ".defaults" do
    let(:tool) do
      Class.new(described_class) do
        name "math"
        parameter :x, Integer, "first number"
        parameter :y, Integer, "second number"
        defaults x: 0, y: 1
      end
    end

    it "sets default values on parameters" do
      props = tool.function.params.properties
      expect(props[:x].default).to eq(0)
      expect(props[:y].default).to eq(1)
    end

    it "raises KeyError for unknown keys" do
      expect {
        Class.new(described_class) do
          name "bad"
          parameter :x, Integer, "value"
          defaults unknown: 42
        end
      }.to raise_error(KeyError, 'key not found: "unknown"')
    end
  end

  describe ".a2a" do
    let(:skill) do
      LLM::A2A::Card::Skill.new(
        "id" => "analyze",
        "name" => "Returns hello world",
        "description" => "Analyze data"
      )
    end
    let(:tool) { described_class.a2a(Object.new, skill) }

    it "inspects as an a2a tool" do
      expect(tool.inspect).to match(/\A<LLM::Tool:0x\h+ name=Returns-hello-world \(a2a\)>\z/)
    end

    it "normalizes spaces in the tool name" do
      expect(tool.name).to eq("Returns-hello-world")
    end

    it "marks generated tools as a2a tools" do
      expect(tool).to be_a2a
    end
  end

  describe ".a2a?" do
    it "returns false for normal tools" do
      expect(shell).to_not be_a2a
    end
  end

  describe ".set" do
    context "with name and description" do
      let(:tool) do
        Class.new(described_class) do
          set name: "hello",
              description: "Says hello"
        end
      end

      it "sets the tool name" do
        expect(tool.name).to eq("hello")
      end

      it "sets the tool description" do
        expect(tool.description).to eq("Says hello")
      end
    end

    context "with parameters from tuples" do
      let(:tool) do
        Class.new(described_class) do
          set name: "math",
              parameters: [
                [:x, Integer, "first number"],
                [:y, Integer, "second number"]
              ]
        end
      end

      it "creates parameters with the correct types" do
        props = tool.function.params.properties
        expect(props[:x]).to be_a(LLM::Schema::Integer)
        expect(props[:y]).to be_a(LLM::Schema::Integer)
      end

      it "sets parameter descriptions" do
        props = tool.function.params.properties
        expect(props[:x].description).to eq("first number")
        expect(props[:y].description).to eq("second number")
      end
    end

    context "with parameter options" do
      let(:tool) do
        Class.new(described_class) do
          set name: "greeter",
              parameters: [
                [:name, String, "the name", {required: true}],
                [:greeting, String, "the greeting", {default: "Hello"}]
              ]
        end
      end

      it "marks a parameter as required" do
        expect(tool.function.params.properties[:name]).to be_required
      end

      it "sets a default value on a parameter" do
        expect(tool.function.params.properties[:greeting].default).to eq("Hello")
      end
    end

    context "with an unknown key" do
      it "raises KeyError" do
        expect {
          Class.new(described_class) do
            set name: "oops",
                bogus: "value"
          end
        }.to raise_error(KeyError)
      end
    end

    context "with required and defaults alongside class-level DSL" do
      let(:tool) do
        Class.new(described_class) do
          parameter :x, Integer, "first"
          parameter :y, Integer, "second"
          set required: [:x],
              defaults: {y: 42}
        end
      end

      it "marks parameters as required" do
        expect(tool.function.params.properties[:x]).to be_required
      end

      it "sets default values" do
        expect(tool.function.params.properties[:y].default).to eq(42)
      end
    end
  end
end
