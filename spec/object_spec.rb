# frozen_string_literal: true

require_relative "setup"

RSpec.describe LLM::Object do
  describe ".from" do
    let(:obj) do
      described_class.from(
        "user" => {
          "name" => "Ava",
          "tags" => ["a", {"k" => 1}]
        },
        "active" => true
      )
    end

    it "wraps nested hashes and arrays" do
      expect(obj).to be_a(described_class)
      expect(obj.user).to be_a(described_class)
      expect(obj.user.name).to eq("Ava")
      expect(obj.user.tags[1]).to be_a(described_class)
      expect(obj.user.tags[1].k).to eq(1)
    end
  end

  describe "key access" do
    let(:obj) { described_class.from("foo" => "bar", :baz => 42) }

    it "provides indifferent access" do
      expect(obj["foo"]).to eq("bar")
      expect(obj[:foo]).to eq("bar")
      expect(obj["baz"]).to eq(42)
      expect(obj[:baz]).to eq(42)
    end

    it "provides method access" do
      expect(obj.foo).to eq("bar")
      expect(obj.baz).to eq(42)
    end

    it "returns nil for missing keys" do
      expect(obj.nope).to be_nil
      expect(obj["nope"]).to be_nil
    end
  end

  describe "#[]=" do
    let(:obj) { described_class.new }

    before { obj[:answer] = 42 }

    it "stores values using string keys" do
      expect(obj["answer"]).to eq(42)
      expect(obj.keys).to eq(["answer"])
    end
  end

  describe "#transform_values!" do
    let(:obj) { described_class.from("foo" => 1, "bar" => 2) }

    it "transforms values in place and returns the underlying hash" do
      expect(obj.transform_values! { |value| value * 10 }).to eq("foo" => 10, "bar" => 20)
      expect(obj.to_h).to eq("foo" => 10, "bar" => 20)
    end
  end

  describe "#to_h and #to_hash" do
    let(:obj) { described_class.from("a" => 1, "b" => 2) }
    let(:h) { obj.to_h }
    let(:t) { obj.to_hash }

    it "returns a duplicate of the underlying hash" do
      expect(h).to eq("a" => 1, "b" => 2)
      expect(t).to eq(a: 1, b: 2)
      expect(h).to_not be(obj.to_h)
    end
  end

  describe "#inspect" do
    let(:obj) { described_class.from("user" => {"name" => "Ava"}, "active" => true) }

    it "includes the object id and properties" do
      expect(obj.inspect).to start_with("#<LLM::Object:0x")
      expect(obj.inspect).to match(/"user"\s*=>\s*#<LLM::Object:0x/)
      expect(obj.inspect).to match(/properties=\{"name"\s*=>\s*"Ava"\}/)
      expect(obj.inspect).to match(/"active"\s*=>\s*true/)
    end
  end

  describe "#freeze" do
    let(:obj) { described_class.from("foo" => {"bar" => ["baz"]}) }

    it "freezes the object and reports it" do
      expect(obj.freeze).to be(obj)
      expect(obj.frozen?).to be(true)
    end

    it "does not freeze an object that was never frozen" do
      expect(obj.frozen?).to be(false)
    end

    it "is ractor-shareable" do
      expect(Ractor.shareable?(obj.freeze)).to be(true)
    end

    it "freezes nested objects, hashes, arrays and strings" do
      obj.freeze
      expect(obj["foo"].frozen?).to be(true)
      expect(obj["foo"]["bar"].frozen?).to be(true)
      expect(obj["foo"]["bar"].first.frozen?).to be(true)
    end

    it "is idempotent" do
      expect(obj.freeze.freeze).to be(obj)
    end
  end

  describe "when frozen" do
    let(:obj) { described_class.from("foo" => "bar").freeze }

    it "raises FrozenError from #[]=" do
      expect { obj[:foo] = "baz" }.to raise_error(FrozenError)
    end

    it "raises FrozenError from #merge!" do
      expect { obj.merge!("baz" => "qux") }.to raise_error(FrozenError)
    end

    it "raises FrozenError from #delete" do
      expect { obj.delete(:foo) }.to raise_error(FrozenError)
    end
  end

  describe "#respond_to?" do
    let(:obj) { described_class.from("foo" => "bar") }

    it "returns true for keys and methods" do
      expect(obj.respond_to?(:foo)).to be(true)
      expect(obj.respond_to?(:to_h)).to be(true)
    end
  end

  describe "#fetch" do
    let(:obj) { described_class.from("foo" => "bar") }

    context "when the key exists" do
      it "returns the value for string keys" do
        expect(obj.fetch("foo")).to eq("bar")
      end

      it "returns the value for symbol keys" do
        expect(obj.fetch(:foo)).to eq("bar")
      end
    end

    context "when the key is missing" do
      it "raises KeyError" do
        expect { obj.fetch("nope") }.to raise_error(KeyError)
      end

      it "returns the default value when given" do
        expect(obj.fetch("nope", "default")).to eq("default")
      end
    end

    it "reads fetch as an attribute when no argument is given" do
      obj.fetch = 123
      expect(obj.fetch).to eq(123)
    end
  end

  describe "#merge" do
    let(:obj) { described_class.from("foo" => "bar") }

    it "returns a new object with merged values" do
      merged = obj.merge("baz" => 42)
      expect(merged).to be_a(described_class)
      expect(merged.foo).to eq("bar")
      expect(merged.baz).to eq(42)
      expect(obj.baz).to be_nil
    end

    it "raises TypeError when the argument is not hash-like" do
      expect { obj.merge(1) }.to raise_error(TypeError, /cannot be coerced into a Hash/)
    end

    it "reads merge as an attribute when no argument is given" do
      obj.merge = 123
      expect(obj.merge).to eq(123)
    end
  end

  describe "#delete" do
    let(:obj) { described_class.from("foo" => "bar", "baz" => 42) }

    it "deletes a key using indifferent access" do
      expect(obj.delete(:foo)).to eq("bar")
      expect(obj.foo).to be_nil
      expect(obj.keys).to eq(["baz"])
    end

    it "still allows delete= as a dynamic attribute writer" do
      obj.delete = 123
      expect(obj["delete"]).to eq(123)
    end

    it "reads delete as an attribute when delete= assigned it" do
      obj.delete = 123
      expect(obj.delete).to eq(123)
    end
  end

  describe "built-in method names" do
    let(:obj) { described_class.from("keys" => 123) }

    it "returns the underlying keys" do
      expect(obj.keys).to eq(["keys"])
    end
  end

  describe "when given 'method_missing' as a key" do
    let(:obj) { described_class.from("method_missing" => "bar", "foo" => "baz") }

    it "reads the stored method_missing value" do
      expect(obj.method_missing).to eq("bar")
    end

    it "still reads other dynamic keys" do
      expect(obj.foo).to eq("baz")
    end
  end

  describe "#key?" do
    let(:obj) { described_class.from("key?" => 123) }

    it "reads key? as an attribute when no argument is given" do
      expect(obj.key?).to eq(123)
    end
  end

  describe "Enumerable" do
    let(:obj) { described_class.from("a" => 1, "b" => 2, "c" => 3) }

    context "when iterating" do
      let(:pairs) do
        [].tap { |arr| obj.each { |k, v| arr << [k, v] } }
      end

      it "yields key-value pairs" do
        expect(pairs).to contain_exactly(["a", 1], ["b", 2], ["c", 3])
      end
    end

    context "when using enumerable helpers" do
      let(:mapped) { obj.map { |k, v| "#{k}=#{v}" } }
      let(:selected) { obj.select { |_, v| v.odd? } }

      it "supports map" do
        expect(mapped).to contain_exactly("a=1", "b=2", "c=3")
      end

      it "supports select" do
        expect(selected).to contain_exactly(["a", 1], ["c", 3])
      end
    end
  end
end
