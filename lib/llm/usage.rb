# frozen_string_literal: true

##
# This class helps track the number of input,
# output, reasoning, cache, and overall token
# count for a {LLM::Context} or {LLM::Agent}
# object.
class LLM::Usage
  ##
  # @return [Array<String>]
  FIELDS = %w[
    input_tokens output_tokens
    reasoning_tokens input_audio_tokens
    output_audio_tokens input_image_tokens
    cache_read_tokens cache_write_tokens
    total_tokens
  ].freeze
  private_constant :FIELDS

  ##
  # @return [Array<String>]
  def self.fields
    USAGE
  end

  ##
  # @return [LLM::Usage]
  def self.zero
    new(
      input_tokens: 0, output_tokens: 0,
      reasoning_tokens: 0, input_audio_tokens: 0,
      output_audio_tokens: 0, input_image_tokens: 0,
      cache_read_tokens: 0, cache_write_tokens: 0,
      total_tokens: 0
    )
  end


  ##
  # @param [#to_h] obj
  # @return [LLM::Usage]
  def self.from(obj)
    if LLM::Usage === obj
      obj
    elsif obj.respond_to?(:to_h)
      new(**obj.to_h.transform_keys(&:to_sym))
    else
      raise TypeError, "The given object (an instance " \
                       "of '#{obj.class}') cannot be "  \
                       "coerced into an LLM::Usage "    \
                       "object"
    end
  end

  ##
  # @param [Integer] input_tokens
  # @param [Integer] output_tokens
  # @param [Integer] reasoning_tokens
  # @param [Integer] input_audio_tokens
  # @param [Integer] output_audio_tokens
  # @param [Integer] input_image_tokens
  # @param [Integer] cache_read_tokens
  # @param [Integer] cache_write_tokens
  # @param [Integer] total_tokens
  # @return [LLM::Usage]
  def initialize(input_tokens: 0, output_tokens: 0, reasoning_tokens: 0,
                 input_audio_tokens: 0, output_audio_tokens: 0,
                 input_image_tokens: 0, cache_read_tokens: 0,
                 cache_write_tokens: 0, total_tokens: 0)
    @input_tokens = input_tokens
    @output_tokens = output_tokens
    @reasoning_tokens = reasoning_tokens
    @input_audio_tokens = input_audio_tokens
    @output_audio_tokens = output_audio_tokens
    @input_image_tokens = input_image_tokens
    @cache_read_tokens = cache_read_tokens
    @cache_write_tokens = cache_write_tokens
    @total_tokens = total_tokens
  end

  ##
  # @return [Integer]
  def input_tokens
    @input_tokens || 0
  end

  ##
  # @return [Integer]
  def output_tokens
    @output_tokens || 0
  end

  ##
  # @return [Integer]
  def reasoning_tokens
    @reasoning_tokens || 0
  end

  ##
  # @return [Integer]
  def input_audio_tokens
    @input_audio_tokens || 0
  end

  ##
  # @return [Integer]
  def output_audio_tokens
    @output_audio_tokens || 0
  end

  ##
  # @return [Integer]
  def input_image_tokens
    @input_image_tokens || 0
  end

  ##
  # @return [Integer]
  def cache_read_tokens
    @cache_read_tokens || 0
  end

  ##
  # @return [Integer]
  def cache_write_tokens
    @cache_write_tokens || 0
  end

  ##
  # @return [Integer]
  def total_tokens
    @total_tokens || 0
  end

  ##
  # Returns a new {LLM::Usage} that is the sum of this
  # usage and another. Missing (nil) fields are zero.
  # @param [LLM::Usage, Object, nil] other
  # @return [LLM::Usage]
  def +(other)
    other = self.class.from(other)
    LLM::Usage.new(
      input_tokens: input_tokens + other.input_tokens,
      output_tokens: output_tokens + other.output_tokens,
      reasoning_tokens: reasoning_tokens + other.reasoning_tokens,
      input_audio_tokens: input_audio_tokens + other.input_audio_tokens,
      output_audio_tokens: output_audio_tokens + other.output_audio_tokens,
      input_image_tokens: input_image_tokens + other.input_image_tokens,
      cache_read_tokens: cache_read_tokens + other.cache_read_tokens,
      cache_write_tokens: cache_write_tokens + other.cache_write_tokens,
      total_tokens: total_tokens + other.total_tokens
    )
  end

  ##
  # @return [Boolean]
  #  Returns true when two usages hold the same token counts
  def ==(other)
    other.is_a?(LLM::Usage) and other.to_h == to_h
  end
  alias_method :eql?, :==

  ##
  # @return [Integer]
  #  Returns a hash consistent with {#eql?}
  def hash
    to_h.hash
  end

  ##
  # @return [Hash]
  def to_h
    {
      input_tokens:, output_tokens:,
      reasoning_tokens:,
      input_audio_tokens:, output_audio_tokens:, input_image_tokens:,
      cache_read_tokens:, cache_write_tokens:, total_tokens:
    }
  end

  ##
  # @return [String]
  def to_json(...)
    LLM.json.dump(to_h, ...)
  end
end
