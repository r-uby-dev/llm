# frozen_string_literal: true

module LLM::Sequel
  ##
  # Sequel plugin for persisting {LLM::Agent LLM::Agent} state.
  #
  # This wrapper reuses the same record-backed runtime surface as
  # {LLM::Sequel::Plugin}, but builds an {LLM::Agent LLM::Agent} instead of an
  # {LLM::Context LLM::Context}. Agent defaults such as model, tools, schema,
  # instructions, and concurrency are configured on an internal agent subclass.
  module Agent
    require_relative "plugin"
    EMPTY_HASH = LLM::Sequel::Plugin::EMPTY_HASH
    DEFAULTS = LLM::Sequel::Plugin::DEFAULTS
    Utils = LLM::Sequel::Plugin::Utils

    def self.apply(model, **)
      model.extend ClassMethods
      model.include LLM::Sequel::Plugin::InstanceMethods
      model.include InstanceMethods
    end

    def self.configure(model, options = EMPTY_HASH, &block)
      options = DEFAULTS.merge(options)
      model.db.extension :pg_json if %i[json jsonb].include?(options[:format])
      model.instance_variable_set(:@llm_agent_options, options.freeze)
      block_given? ? model.instance_exec(model.agent, &block) : nil
    end

    module ClassMethods
      def llm_plugin_options
        @llm_agent_options || Agent::DEFAULTS
      end

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
      #   class Agent < Sequel::Model
      #     plugin :llm_agent
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

    module InstanceMethods
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

      def ctx
        @ctx ||= begin
          options = self.class.llm_plugin_options
          columns = Agent::Utils.columns(options)
          params = Agent::Utils.resolve_options(self, options[:context], Agent::EMPTY_HASH).dup
          ctx = self.class.agent.new(llm, params.compact.merge(record: self))
          data = self[columns[:data_column]]
          if data.nil? || data == ""
            ctx
          else
            case options[:format]
            when :string then ctx.restore(string: data)
            when :json, :jsonb then ctx.restore(data:)
            else raise ArgumentError, "Unknown format: #{options[:format].inspect}"
            end
          end
        end
      end
    end
  end
end
