# frozen_string_literal: true

# @!parse
#   module ::ActiveRecord
#     class Base
#     end
#   end

module LLM::ActiveRecord
  ##
  # ActiveRecord integration for persisting {LLM::Agent LLM::Agent} state.
  #
  # This wrapper reuses the same record-backed runtime surface as
  # {LLM::ActiveRecord::ActsAsLLM}, but builds an {LLM::Agent LLM::Agent}
  # instead of an {LLM::Context LLM::Context}. Agent defaults such as model,
  # tools, schema, instructions, and concurrency are configured on the model
  # class and forwarded to an internal agent subclass.
  module ActsAsAgent
    module ClassMethods
      ##
      # @return [Class<LLM::Agent>]
      def agent
        @agent ||= Class.new(LLM::Agent)
      end

      ##
      # Bulk-assign class-level agent defaults.
      #
      # Each key is resolved by calling the corresponding class method on the
      # internal agent subclass.
      #
      # @example
      #   class Agent < ApplicationRecord
      #     acts_as_agent
      #     set instructions: "You are a system administrator",
      #         model: "gpt-4.1-nano",
      #         tools: [Shell]
      #   end
      #
      # @param [Hash] properties
      # @option properties [String] :instructions
      # @option properties [String] :model
      # @option properties [Array<LLM::Function>] :tools
      # @option properties [Array<String>] :skills
      # @option properties [#to_json] :schema
      # @option properties [Symbol, Array<Symbol>] :concurrency
      # @option properties [LLM::Tracer, Proc] :tracer
      # @option properties [Object, Proc] :stream
      # @option properties [String, Symbol, Array<String, Symbol>, Proc] :confirm
      # @raise [KeyError] when a property key does not match a class-level accessor
      # @return [void]
      def set(properties)
        agent.set(properties)
      end
    end

    module Hooks
      ##
      # Called when hooks are extended onto an ActiveRecord model.
      #
      # @param [Class] model
      # @return [void]
      def self.extended(model)
        model.include LLM::ActiveRecord::ActsAsLLM::InstanceMethods unless model.ancestors.include?(LLM::ActiveRecord::ActsAsLLM::InstanceMethods)
        model.include InstanceMethods unless model.ancestors.include?(InstanceMethods)
        model.extend ClassMethods unless model.singleton_class.ancestors.include?(ClassMethods)
      end
    end

    ##
    # Installs the `acts_as_agent` wrapper on an ActiveRecord model.
    #
    # @param [Hash] options
    # @option options [Symbol] :format
    #   Storage format for the serialized agent state. Use `:string` for text
    #   columns, or `:json` / `:jsonb` for structured JSON columns with
    #   ActiveRecord JSON typecasting enabled.
    # @option options [Proc, Symbol, LLM::Tracer, nil] :tracer
    #   Optional tracer, method name, or proc that resolves to one and is
    #   assigned through `llm.tracer = ...` on the resolved provider.
    # @option options [Proc, Symbol, LLM::Provider] :provider
    #   Must resolve to an `LLM::Provider` instance for the current record.
    # @yield
    #   Evaluated in the model class after the wrapper is installed, so agent
    #   DSL methods such as `model`, `tools`, `schema`, `instructions`, and
    #   `concurrency` can be configured inline.
    # @yieldparam [LLM::Agent] agent
    #  Yields an instance of {LLM::Agent LLM::Agent}.
    # @return [void]
    def acts_as_agent(options = EMPTY_HASH, &block)
      options = DEFAULTS.merge(options)
      class_attribute :llm_plugin_options, instance_accessor: false, default: DEFAULTS unless respond_to?(:llm_plugin_options)
      self.llm_plugin_options = options.freeze
      extend Hooks
      block_given? ? class_exec(agent, &block) : nil
    end

    module InstanceMethods
      ##
      # Returns the resolved provider instance for this record.
      # @return [LLM::Provider]
      def llm
        options = self.class.llm_plugin_options
        return @llm if @llm
        @llm = Utils.resolve_provider(self, options, EMPTY_HASH)
        @llm.tracer = Utils.resolve_option(self, options[:tracer]) if options[:tracer]
        @llm
      end

      ##
      # @note
      #  This method does not persist to the database,
      #  but it can inspect and alter runtime state in
      #  a way that is temporary.
      # @param (see LLM::Agent#console)
      # @return (see LLM::Agent#console)
      def console(**params)
        ctx.console(**params)
      end
      alias_method :repl, :console

      private

      ##
      # @return [LLM::Agent]
      def ctx
        @ctx ||= begin
          options = self.class.llm_plugin_options
          params = Utils.resolve_options(self, options[:context], EMPTY_HASH).dup
          ctx = self.class.agent.new(llm, params.compact.merge(record: self))
          columns = Utils.columns(options)
          data = self[columns[:data_column]]
          if data.nil? || data == ""
            ctx
          else
            case options[:format]
            when :string then ctx.restore(string: data)
            when :json, :jsonb then ctx.restore(data:)
            else raise ArgumentError, "Unknown format: #{options[:format].inspect}"
            end
            ctx
          end
        end
      end
    end
  end
end

# @!parse ::ActiveRecord::Base.extend(LLM::ActiveRecord::ActsAsAgent)
::ActiveRecord::Base.extend(LLM::ActiveRecord::ActsAsAgent)
