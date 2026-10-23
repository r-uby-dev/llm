# frozen_string_literal: true

##
# The {LLM::Object LLM::Object} class encapsulates a Hash object. It is
# similar in spirit to OpenStruct, and it was introduced after OpenStruct
# became a bundled gem rather than a default gem in Ruby 3.5.
class LLM::Object < BasicObject
  require_relative "object/builder"
  require_relative "object/kernel"

  SINGLETON = self
  UNDEFINED = ::Object.new.freeze
  LLM = ::LLM
  private_constant :SINGLETON, :UNDEFINED, :LLM

  ##
  # @api private
  # @param [Hash] h
  # @param [#to_s, #to_sym] k
  # @return [String, Symbol, nil]
  def self.key(h, k)
    return nil if k.nil?
    if h.key?(k.to_s)
      k.to_s
    elsif h.key?(k.to_sym)
      k.to_sym
    else
      nil
    end
  end

  ##
  # @api private
  # @param [Hash] h
  # @param [#to_s, #to_sym] k
  # @return [Object, nil]
  def self.get(h, k)
    name = key(h, k)
    h[name] if name
  end

  extend Builder
  include Kernel
  include ::Enumerable
  defined?(::PP) ? include(::PP::ObjectMixin) : nil

  ##
  # @param [Hash] h
  # @return [LLM::Object]
  def initialize(h = {})
    @h = h || {}
  end

  ##
  # Yields a key|value pair to a block.
  # @yieldparam [Symbol] k
  # @yieldparam [Object] v
  # @return [void]
  def each(&)
    @h.each(&)
  end

  ##
  # In-place transform of values with a block.
  # @yieldparam [Object] v
  # @return [Hash]
  def transform_values!(&)
    @h.transform_values!(&)
  end

  ##
  # @param [Symbol, #to_sym] k
  # @return [Object]
  def [](k)
    @h[SINGLETON.key(@h, k)]
  end

  ##
  # @param [Symbol, #to_sym] k
  # @param [Object] v
  # @return [void]
  def []=(k, v)
    if frozen?
      raise ::FrozenError, "can't modify frozen object"
    else
      @h[k.to_s] = v
    end
  end

  ##
  # @return [String]
  def to_json(...)
    LLM.json.dump(to_h, ...)
  end

  ##
  # @return [Boolean]
  def empty?
    @h.empty?
  end

  ##
  # @return [Hash]
  def to_h
    @h.dup
  end

  ##
  # @return [Hash]
  def to_hash
    @h.transform_keys(&:to_sym)
  end

  ##
  # @return [Array<String>]
  def keys
    @h.keys
  end

  ##
  # @return [Array]
  def values
    @h.values
  end

  ##
  # @param [String, Symbol] k
  # @return [Boolean]
  def key?(k = UNDEFINED)
    return SINGLETON.get(@h, :key?) if k.equal?(UNDEFINED)
    @h.key?(SINGLETON.key(@h, k))
  end
  alias_method :has_key?, :key?

  ##
  # @param [String, Symbol] k
  # @return [Object]
  def fetch(k = UNDEFINED, *args, &b)
    return SINGLETON.get(@h, :fetch) if k.equal?(UNDEFINED)
    key = SINGLETON.key(@h, k)
    @h.fetch(key || k, *args, &b)
  end

  ##
  # @param [Hash, to_h] other
  #  The hash to merge
  # @return [LLM::Object]
  #  Returns a new LLM::Object
  def merge(other = UNDEFINED)
    return SINGLETON.get(@h, :merge) if other.equal?(UNDEFINED)
    other = ::Hash.try_convert(other)
    raise TypeError, "#{other} cannot be coerced into a Hash" unless other
    SINGLETON.from @h.merge(other)
  end

  ##
  # @param [Hash, #to_h] other
  #  The hash to merge in place
  # @return [LLM::Object]
  #  Returns self
  def merge!(other = UNDEFINED)
    if frozen?
      raise ::FrozenError, "can't modify frozen object"
    else
      return SINGLETON.get(@h, :merge!) if other.equal?(UNDEFINED)
      other = ::Hash.try_convert(other)
      raise TypeError, "#{other} cannot be coerced into a Hash" unless other
      @h.merge!(other)
      self
    end
  end

  ##
  # @param [#to_s, #to_sym] k
  #  The key name
  # @return [void]
  def delete(k = UNDEFINED)
    if frozen?
      raise ::FrozenError, "can't modify frozen object"
    else
      return SINGLETON.get(@h, :delete) if k.equal?(UNDEFINED)
      @h.delete(SINGLETON.key(@h, k))
    end
  end

  ##
  # @return [Integer]
  def size
    @h.size
  end
  alias_method :length, :size

  ##
  # @yieldparam [String, Object]
  def each_pair(&)
    @h.each(&)
  end

  ##
  # @return [Object, nil]
  def dig(*args)
    return SINGLETON.get(@h, :dig) if args.empty?
    @h.dig(*args)
  end

  ##
  # @return [Hash]
  def slice(*args)
    return SINGLETON.get(@h, :slice) if args.empty?
    @h.slice(*args)
  end

  ##
  # @param [Hash, #to_h] other
  # @return [Boolean]
  def ==(other)
    return false unless other.respond_to?(:to_h)
    to_h == other.to_h || to_hash == other.to_h
  end
  alias_method :eql?, :==

  private

  def method_missing(m, *args, &b)
    if m.to_s.end_with?("=")
      self[m[0..-2]] = args.first
    elsif k = SINGLETON.key(@h, m)
      @h[k]
    else
      nil
    end
  end
end
