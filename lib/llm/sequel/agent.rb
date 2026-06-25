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

      def agent
        @agent ||= Class.new(LLM::Agent)
      end
    end

    module InstanceMethods
      private

      def ctx
        @ctx ||= begin
          options = self.class.llm_plugin_options
          columns = Agent::Utils.columns(options)
          params = Agent::Utils.resolve_options(self, options[:context], Agent::EMPTY_HASH).dup
          ctx = self.class.agent.new(llm, params.compact)
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
