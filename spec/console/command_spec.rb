# frozen_string_literal: true

require "setup"
require "llm/console"

RSpec.describe LLM::Console::Command do
  before(:each) { described_class.registry.clear }
  let(:llm) { LLM.deepseek(key: ENV["test"]) }
  let(:agent) { LLM::Agent.new(llm) }
  let(:console) { LLM::Console.new(agent:) }

  describe ".parameter" do
    let(:command) do
      Class.new(described_class) do
        name "example"
        description "an example command"
      end
    end

    before do
      command.parameter :path, String, "A file path"
    end

    it "registers a parameter in .parameters" do
      expect(command.parameters).to have_key(:path)
    end

    it "stores the parameter name" do
      expect(command.parameters[:path].name).to eq(:path)
    end

    it "stores the parameter type" do
      expect(command.parameters[:path].type).to eq(String)
    end

    it "stores the parameter description" do
      expect(command.parameters[:path].description).to eq("A file path")
    end

    it "assigns sequential indices starting from 0" do
      expect(command.parameters[:path].index).to eq(0)

      command.parameter :count, Integer, "A count"
      expect(command.parameters[:count].index).to eq(1)
    end

    context "when given options" do
      before do
        command.parameter :verbose, String, "Verbosity", required: true
      end

      it "passes options through to the parameter" do
        expect(command.parameters[:verbose]).to be_required
      end
    end
  end

  describe ".parameters" do
    context "when no parameters have been defined" do
      let(:command) do
        Class.new(described_class) do
          name "bare"
          description "a bare command"
        end
      end

      it "returns an empty hash" do
        expect(command.parameters).to eq({})
      end
    end

    context "when parameters have been defined" do
      let(:command) do
        Class.new(described_class) do
          name "with_params"
          description "a command with params"
          parameter :path, String, "A file path"
          parameter :count, Integer, "A count"
        end
      end

      it "returns a hash of all defined parameters" do
        expect(command.parameters.keys).to contain_exactly(:path, :count)
      end
    end

    context "when multiple commands define their own parameters" do
      let(:first) do
        Class.new(described_class) do
          name "first"
          parameter :path, String, "A file path"
        end
      end

      let(:second) do
        Class.new(described_class) do
          name "second"
          parameter :count, Integer, "A count"
        end
      end

      before { [first, second] }

      it "isolates parameters between command subclasses" do
        expect(first.parameters.keys).to eq([:path])
        expect(second.parameters.keys).to eq([:count])
      end
    end
  end

  describe ".required" do
    let(:command) do
      Class.new(described_class) do
        name "configure"
        description "configure something"
        parameter :path, String, "A file path"
        parameter :count, Integer, "A count"
      end
    end

    context "when given known parameter names" do
      before { command.required([:path]) }

      it "marks the named parameter as required" do
        expect(command.parameters[:path]).to be_required
      end

      it "leaves other parameters unchanged" do
        expect(command.parameters[:count]).not_to be_required
      end
    end

    context "when given an unknown parameter name" do
      it "raises an LLM::Error" do
        expect { command.required([:unknown]) }
          .to raise_error(LLM::Error, "'unknown' is not a known parameter")
      end
    end
  end

  describe "#parameters" do
    let(:klass) do
      Class.new(described_class) do
        name "demo"
        description "a demo command"
        parameter :path, String, "A file path"
      end
    end

    let(:command) { klass.new(console) }

    it "delegates to the class-level parameters" do
      expect(command.parameters).to eq(klass.parameters)
    end
  end

  describe "#call" do
    let(:command) { described_class.new(console) }

    it "raises NotImplementedError" do
      expect { command.call }
        .to raise_error(NotImplementedError, /#call is not implemented/)
    end
  end

  describe "subclass aliases" do
    it "inherits description from the parent command" do
      expect(LLM::Console::Command::Quit.description).to eq("exits the console")
    end
  end
end

RSpec.describe LLM::Console::Command::Parameter do
  let(:parameter) do
    described_class.new(:path, String, "A file path", {}, 0, nil)
  end

  describe "#required?" do
    subject { parameter.required? }

    context "when the parameter is not required" do
      it { is_expected.to be(false) }
    end

    context "when the parameter is required" do
      before { parameter.required! }
      it { is_expected.to be(true) }
    end
  end

  describe "#required!" do
    it "flags the parameter as required" do
      expect { parameter.required! }
        .to change { parameter.required? }.from(false).to(true)
    end
  end

  describe "#value=" do
    context "when the value matches the type" do
      it "assigns a String value" do
        parameter.value = "/tmp/foo"
        expect(parameter.value).to eq("/tmp/foo")
      end
    end

    context "when the value does not match the type" do
      it "raises a TypeError" do
        expect { parameter.value = 42 }
          .to raise_error(TypeError, "Integer is not a String")
      end
    end

    context "with a parameter of type Integer" do
      let(:parameter) do
        described_class.new(:count, Integer, "A count", {}, 0, nil)
      end

      it "accepts an Integer value" do
        parameter.value = 5
        expect(parameter.value).to eq(5)
      end

      it "rejects a String value" do
        expect { parameter.value = "five" }
          .to raise_error(TypeError, "String is not a Integer")
      end
    end
  end
end
