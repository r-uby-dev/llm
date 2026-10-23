# frozen_string_literal: true

require "setup"

RSpec.describe LLM::Registry do
  let(:registry) { LLM::Registry.for(provider) }

  shared_examples "model exists" do |model|
    context "#cost" do
      context "when given the #{model} model" do
        it "returns an object" do
          expect(
            registry.cost(model:)
          ).to be_instance_of(LLM::Object)
        end
      end
    end
  end

  shared_examples "fallback exists" do |model, fallback|
    context "#cost" do
      context "when given the #{model} model" do
        it "returns the #{fallback} cost object" do
          expect(
            registry.cost(model:)
          ).to eq(registry.cost(model: fallback))
        end
      end
    end
  end

  context "when given openai" do
    let(:provider) { :openai }

    include_examples "model exists", "gpt-4.1"
    include_examples "model exists", "gpt-5.3-codex"
    include_examples "fallback exists", "gpt-4.1-2025-01-01", "gpt-4.1"
    include_examples "fallback exists", "gpt-4-0613", "gpt-4"
  end

  context "when given google" do
    let(:provider) { :google }

    include_examples "model exists", "gemini-3.1-pro-preview-customtools"
    include_examples "model exists", "gemini-embedding-001"
  end

  context "when given anthropic" do
    let(:provider) { :anthropic }

    include_examples "model exists", "claude-opus-5"
    include_examples "model exists", "claude-haiku-4-5-20251001"
  end

  context "when given deepseek" do
    let(:provider) { :deepseek }

    include_examples "model exists", "deepseek-v4-flash"
    include_examples "model exists", "deepseek-v4-pro"
  end

  context "when given xai" do
    let(:provider) { :xai }

    include_examples "model exists", "grok-4.3"
    include_examples "model exists", "grok-4.20-0309-non-reasoning"
  end

  context "when given zai" do
    let(:provider) { :zai }

    include_examples "model exists", "glm-5"
    include_examples "model exists", "glm-4.5-air"
  end

  context "when given moonshot" do
    let(:provider) { :moonshot }

    include_examples "model exists", "kimi-k3"
    include_examples "model exists", "kimi-k2.6"
  end

  context "when given openrouter" do
    let(:provider) { :openrouter }

    include_examples "model exists", "openrouter/free"

    it "includes the automatic router" do
      expect(registry.keys).to include("openrouter/auto")
    end
  end

  context "when given alibaba" do
    let(:provider) { :alibaba }

    include_examples "model exists", "qwen3.6-flash"
    include_examples "model exists", "qwen3-max"
  end

  context "when given bedrock" do
    let(:provider) { :bedrock }

    include_examples "model exists", "anthropic.claude-sonnet-4-5-20250929-v1:0"
    include_examples "model exists", "meta.llama3-3-70b-instruct-v1:0"
  end

  describe "#keys" do
    let(:provider) { :openai }

    subject { registry.keys }

    it "returns the model names" do
      expect(subject).to include("gpt-4.1")
    end
  end

  describe "#models" do
    let(:provider) { :openai }

    subject(:models) { registry.models }

    it "returns registry models" do
      expect(models).to all(be_a(LLM::Registry::Model))
    end

    it "exposes the model ids" do
      expect(models.map(&:id)).to include("gpt-4.1")
    end
  end

  describe LLM::Registry::Model do
    subject(:model) { LLM::Registry.for(:openai).models.find { it.id == "gpt-4.1" } }

    it "exposes a display name" do
      expect(model.name).to be_a(String)
    end

    it "exposes the context window" do
      expect(model.context_window).to be_a(Integer)
    end

    it "exposes the cost object" do
      expect(model.cost).to be_a(LLM::Object)
    end

    it "exposes the input and output costs" do
      expect(model.input_cost).to be_a(Numeric)
      expect(model.output_cost).to be_a(Numeric)
    end

    it "orders cheaper models before expensive ones" do
      cheap = LLM::Registry.for(:openai).models.find { it.id == "gpt-4o-mini" }
      expensive = LLM::Registry.for(:openai).models.find { it.id == "o1-pro" }
      expect(cheap).to be < expensive
    end

    it "sorts unpriced models after priced ones" do
      registry = LLM::Registry.for(:openai)
      priced = registry.models.find { !it.input_cost.nil? }
      unpriced = registry.models.find { it.input_cost.nil? }
      expect(priced).to be < unpriced
    end

    it "identifies a text LLM from both directions" do
      model = LLM::Registry.for(:openai).models.find { it.id == "gpt-4.1" }
      expect(model.text?).to be(true)
    end

    it "excludes generation models from text?" do
      model = LLM::Registry.for(:google).models.find { it.id == "gemini-3.1-flash-tts-preview" }
      expect(model.text?).to be(false)
    end

    it "reports a modality supported on either side" do
      model = LLM::Registry.for(:alibaba).models.find { it.id == "qwen3.8-max" }
      expect(model.pdf?).to be(true)
    end

    it "distinguishes input from output support" do
      model = LLM::Registry.for(:openai).models.find { it.id == "gpt-4.1" }
      expect(model.input?("pdf")).to be(true)
      expect(model.output?("image")).to be(false)
    end
  end
end
