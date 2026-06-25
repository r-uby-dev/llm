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
      def model(model = nil, &block)
        return agent.model if model.nil? && !block
        agent.model(model, &block)
      end

      def tools(*tools, &block)
        return agent.tools if tools.empty? && !block
        agent.tools(*tools, &block)
      end

      def skills(*skills, &block)
        return agent.skills if skills.empty? && !block
        agent.skills(*skills, &block)
      end

      def schema(schema = nil, &block)
        return agent.schema if schema.nil? && !block
        agent.schema(schema, &block)
      end

      def instructions(instructions = nil)
        return agent.instructions if instructions.nil?
        agent.instructions(instructions)
      end

      def concurrency(concurrency = nil)
        return agent.concurrency if concurrency.nil?
        agent.concurrency(concurrency)
      end

      def confirm(*tool_names, &block)
        return agent.confirm if tool_names.empty? && !block
        agent.confirm(*tool_names, &block)
      end

      def tracer(tracer = nil, &block)
        return agent.tracer if tracer.nil? && !block
        agent.tracer(tracer, &block)
      end

      def agent
        @agent ||= Class.new(LLM::Agent)
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

      private

      ##
      # @return [LLM::Agent]
      def ctx
        @ctx ||= begin
          options = self.class.llm_plugin_options
          params = Utils.resolve_options(self, options[:context], EMPTY_HASH).dup
          ctx = self.class.agent.new(llm, params.compact)
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
