# frozen_string_literal: true

module LLM::ActiveRecord
  EMPTY_HASH = {}.freeze
  DEFAULTS = {
    data_column: :data,
    format: :string,
    tracer: nil,
    provider: :set_provider,
    context: :set_context,
  }.freeze

  ##
  # These utilities keep persistence plumbing out of the wrapped model's
  # method namespace so the injected surface stays focused on the runtime
  # API itself.
  # @api private
  module Utils
    ##
    # Resolves a single configured option against a model instance.
    # @return [Object]
    def self.resolve_option(obj, option)
      LLM::Utils.resolve_option(obj, option)
    end

    ##
    # Resolves hash-like wrapper options against a model instance.
    # @return [Hash]
    def self.resolve_options(obj, option, empty_hash)
      case option
      when Proc, Symbol, Hash then resolve_option(obj, option)
      else empty_hash.dup
      end
    end

    ##
    # Serializes the runtime into the configured storage format.
    # @return [String, Hash]
    def self.serialize_context(ctx, format)
      case format
      when :string then ctx.to_json
      when :json, :jsonb then ctx.to_h
      else raise ArgumentError, "Unknown format: #{format.inspect}"
      end
    end

    ##
    # Maps wrapper options onto the record's storage columns.
    # @return [Hash]
    def self.columns(options)
      {
        data_column: options[:data_column]
      }.freeze
    end

    ##
    # Resolves the provider runtime for a record.
    # @return [LLM::Provider]
    def self.resolve_provider(obj, options, empty_hash)
      provider = resolve_option(obj, options[:provider])
      return provider if LLM::Provider === provider
      raise ArgumentError, "provider: must resolve to an LLM::Provider instance"
    end

    ##
    # Persists the runtime state and usage columns back onto the record.
    # @return [void]
    def self.save!(obj, ctx, options)
      columns = self.columns(options)
      obj.assign_attributes(columns[:data_column] => serialize_context(ctx, options[:format]))
      obj.save!
    end
  end

  require "llm/active_record/acts_as_llm"
  require "llm/active_record/acts_as_agent"
end
